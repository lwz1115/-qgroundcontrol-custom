from __future__ import annotations

import queue
import shutil
import socket
import struct
import subprocess
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

MAVLINK_V1_MAGIC = 0xFE
MAVLINK_V2_MAGIC = 0xFD
MAVLINK_V2_SIGNATURE_FLAG = 0x01
MSG_PARAM_VALUE = 22
MSG_RC_CHANNELS_RAW = 35
MSG_RC_CHANNELS = 65
MSG_PID_TUNING = 194
RC_CHANNEL_COUNT = 16
PID_PARAM_KEYWORDS = ("PID", "ATC_", "PSC_", "RAT_", "TUNE")
PID_TUNING_AXES = {1: "ROLL", 2: "PITCH", 3: "YAW", 4: "ACCZ", 5: "STEER", 6: "LANDING"}


class MavlinkFrameParser:
    """Split raw UDP payloads into individual MAVLink v1/v2 messages."""

    def __init__(self) -> None:
        self._buffer = bytearray()

    def feed(self, data: bytes) -> list[tuple[int, bytes]]:
        self._buffer.extend(data)
        messages: list[tuple[int, bytes]] = []
        while True:
            frame = self._take_frame()
            if frame is None:
                break
            messages.append(frame)
        if len(self._buffer) > 8192:
            del self._buffer[: len(self._buffer) - 4096]
        return messages

    def _take_frame(self) -> tuple[int, bytes] | None:
        buffer = self._buffer
        start = 0
        while start < len(buffer) and buffer[start] not in (MAVLINK_V1_MAGIC, MAVLINK_V2_MAGIC):
            start += 1
        if start:
            del buffer[:start]
        if not buffer:
            return None
        if buffer[0] == MAVLINK_V2_MAGIC:
            return self._take_v2_frame()
        return self._take_v1_frame()

    def _take_v1_frame(self) -> tuple[int, bytes] | None:
        buffer = self._buffer
        if len(buffer) < 8:
            return None
        payload_length = buffer[1]
        frame_length = payload_length + 8
        if len(buffer) < frame_length:
            return None
        message_id = buffer[5]
        payload = bytes(buffer[6 : 6 + payload_length])
        del buffer[:frame_length]
        return message_id, payload

    def _take_v2_frame(self) -> tuple[int, bytes] | None:
        buffer = self._buffer
        if len(buffer) < 12:
            return None
        payload_length = buffer[1]
        signature_length = 13 if buffer[2] & MAVLINK_V2_SIGNATURE_FLAG else 0
        frame_length = payload_length + 12 + signature_length
        if len(buffer) < frame_length:
            return None
        message_id = buffer[7] | (buffer[8] << 8) | (buffer[9] << 16)
        payload = bytes(buffer[10 : 10 + payload_length])
        del buffer[:frame_length]
        return message_id, payload


class WirelessDebugAssistant:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("无线调试助手")
        self.root.geometry("860x620")
        self.root.minsize(760, 500)
        self._socket: socket.socket | None = None
        self._worker: threading.Thread | None = None
        self._stop = threading.Event()
        self._events: queue.Queue[tuple[str, str]] = queue.Queue()
        self._log_file = None
        self._packets = 0
        self._bytes = 0
        self._started_at = ""
        self._paired = False
        self._parser = MavlinkFrameParser()
        self._channels = [0] * RC_CHANNEL_COUNT
        self._channel_vars = [tk.StringVar(value="--") for _ in range(RC_CHANNEL_COUNT)]
        self._channel_bars: list[ttk.Progressbar] = []
        self._pid_params: dict[str, float] = {}
        self._pid_tuning: dict[int, tuple[float, float, float, float, float, float]] = {}
        self._pid_param_rows: dict[str, str] = {}
        self._pid_tuning_rows: dict[int, str] = {}
        self._telemetry_dirty = False
        self._rc_frames = 0
        self._tuning_frames = 0
        self._last_channel_log = 0.0

        self.remote_ip = tk.StringVar(value="192.168.10.1")
        self.pairing_port = tk.StringVar(value="")
        self.connect_port = tk.StringVar(value="")
        self.pair_code = tk.StringVar()
        self.listen_port = tk.StringVar(value="14552")
        self.log_dir = tk.StringVar(value=str(Path.home() / "Desktop" / "QGC_Wireless_Logs"))
        self.status = tk.StringVar(value="未启动")
        self.packet_count = tk.StringVar(value="数据包: 0    字节: 0")
        self.telemetry_summary = tk.StringVar(value="等待遥控器 MAVLink 数据…")
        self._build_ui()
        self.root.after(100, self._drain_events)
        self.root.after(100, self._refresh_telemetry)
        self.root.protocol("WM_DELETE_WINDOW", self._close)

    def _build_ui(self) -> None:
        notebook = ttk.Notebook(self.root)
        notebook.pack(fill="both", expand=True, padx=12, pady=12)
        connection_tab = ttk.Frame(notebook, padding=10)
        telemetry_tab = ttk.Frame(notebook, padding=10)
        notebook.add(connection_tab, text="连接调试")
        notebook.add(telemetry_tab, text="通道 / PID")
        self._build_connection_tab(connection_tab)
        self._build_telemetry_tab(telemetry_tab)

    def _build_connection_tab(self, main: ttk.Frame) -> None:
        settings = ttk.LabelFrame(main, text="连接设置", padding=10)
        settings.pack(fill="x")
        fields = [
            ("遥控器 IP", self.remote_ip),
            ("配对端口", self.pairing_port),
            ("连接端口", self.connect_port),
            ("配对码", self.pair_code),
            ("本地监听端口", self.listen_port),
            ("日志目录", self.log_dir),
        ]
        for row, (label, variable) in enumerate(fields):
            ttk.Label(settings, text=label, width=14).grid(row=row, column=0, sticky="w", pady=4)
            entry = ttk.Entry(settings, textvariable=variable, width=42)
            entry.grid(row=row, column=1, sticky="ew", pady=4)
            if label == "连接端口":
                self.connect_port_entry = entry
                entry.configure(state="disabled")
            if label == "日志目录":
                ttk.Button(settings, text="选择", command=self._choose_log_dir).grid(row=row, column=2, padx=6)
        settings.columnconfigure(1, weight=1)

        actions = ttk.Frame(main, padding=(0, 10, 0, 8))
        actions.pack(fill="x")
        self.pair_button = ttk.Button(actions, text="1. 配对", command=self._pair_only)
        self.pair_button.pack(side="left")
        self.start_button = ttk.Button(actions, text="2. 连接并监听", command=self._start, state="disabled")
        self.start_button.pack(side="left", padx=8)
        self.stop_button = ttk.Button(actions, text="停止", command=self._stop_capture, state="disabled")
        self.stop_button.pack(side="left", padx=8)
        ttk.Label(actions, textvariable=self.status).pack(side="left", padx=12)
        ttk.Label(actions, textvariable=self.packet_count).pack(side="right")

        self.output = tk.Text(main, wrap="none", state="disabled", font=("Consolas", 9))
        self.output.pack(fill="both", expand=True)
        scrollbar = ttk.Scrollbar(self.output, orient="vertical", command=self.output.yview)
        scrollbar.pack(side="right", fill="y")
        self.output.configure(yscrollcommand=scrollbar.set)

        ttk.Label(main, text="日志同时保存原始十六进制数据和可识别的 MAVLink 帧头，便于后续解析。", foreground="#555").pack(
            anchor="w", pady=(8, 0)
        )

    def _build_telemetry_tab(self, tab: ttk.Frame) -> None:
        ttk.Label(tab, textvariable=self.telemetry_summary, foreground="#333").pack(anchor="w")

        body = ttk.Frame(tab)
        body.pack(fill="both", expand=True, pady=(8, 0))
        body.rowconfigure(0, weight=1)
        body.columnconfigure(1, weight=1)

        channels = ttk.LabelFrame(body, text="遥控器通道（16 通道实时）", padding=8)
        channels.grid(row=0, column=0, sticky="nsew", padx=(0, 10))
        channels.columnconfigure(2, weight=1)
        for index in range(RC_CHANNEL_COUNT):
            ttk.Label(channels, text=f"CH{index + 1}", width=5).grid(row=index, column=0, sticky="w", pady=1)
            ttk.Label(channels, textvariable=self._channel_vars[index], width=6, anchor="e").grid(
                row=index, column=1, sticky="e", pady=1
            )
            bar = ttk.Progressbar(channels, maximum=2000, length=150)
            bar.grid(row=index, column=2, sticky="ew", padx=(6, 0), pady=1)
            self._channel_bars.append(bar)

        pid = ttk.Frame(body)
        pid.grid(row=0, column=1, sticky="nsew")
        pid.rowconfigure(0, weight=1)
        pid.rowconfigure(1, weight=1)
        pid.columnconfigure(0, weight=1)

        params = ttk.LabelFrame(pid, text="PID 相关参数（PARAM_VALUE）", padding=8)
        params.grid(row=0, column=0, sticky="nsew", pady=(0, 8))
        self.pid_param_tree = ttk.Treeview(params, columns=("name", "value"), show="headings", height=10)
        self.pid_param_tree.heading("name", text="参数")
        self.pid_param_tree.heading("value", text="值")
        self.pid_param_tree.column("name", width=200, anchor="w")
        self.pid_param_tree.column("value", width=110, anchor="e")
        self.pid_param_tree.pack(side="left", fill="both", expand=True)
        param_scroll = ttk.Scrollbar(params, orient="vertical", command=self.pid_param_tree.yview)
        param_scroll.pack(side="right", fill="y")
        self.pid_param_tree.configure(yscrollcommand=param_scroll.set)

        tuning = ttk.LabelFrame(pid, text="PID 实时调参（PID_TUNING）", padding=8)
        tuning.grid(row=1, column=0, sticky="nsew")
        tuning_columns = (
            ("axis", "轴", 70),
            ("p", "P", 70),
            ("i", "I", 70),
            ("d", "D", 70),
            ("ff", "FF", 70),
            ("desired", "期望", 80),
            ("achieved", "实际", 80),
        )
        self.pid_tuning_tree = ttk.Treeview(
            tuning, columns=[column[0] for column in tuning_columns], show="headings", height=8
        )
        for name, text, width in tuning_columns:
            self.pid_tuning_tree.heading(name, text=text)
            self.pid_tuning_tree.column(name, width=width, anchor="e")
        self.pid_tuning_tree.pack(side="left", fill="both", expand=True)
        tuning_scroll = ttk.Scrollbar(tuning, orient="vertical", command=self.pid_tuning_tree.yview)
        tuning_scroll.pack(side="right", fill="y")
        self.pid_tuning_tree.configure(yscrollcommand=tuning_scroll.set)

    def _process_mavlink(self, payload: bytes) -> None:
        for message_id, message_payload in self._parser.feed(payload):
            if message_id == MSG_RC_CHANNELS:
                self._handle_rc_channels(message_payload)
            elif message_id == MSG_RC_CHANNELS_RAW:
                self._handle_rc_channels_raw(message_payload)
            elif message_id == MSG_PARAM_VALUE:
                self._handle_param_value(message_payload)
            elif message_id == MSG_PID_TUNING:
                self._handle_pid_tuning(message_payload)

    def _handle_rc_channels(self, payload: bytes) -> None:
        if len(payload) < 42:
            return
        unpacked = struct.unpack_from("<I18HBB", payload, 0)
        self._rc_frames += 1
        self._update_channels(list(unpacked[1:19]))

    def _handle_rc_channels_raw(self, payload: bytes) -> None:
        if len(payload) < 22 or self._rc_frames:
            return
        unpacked = struct.unpack_from("<I8HBB", payload, 0)
        self._update_channels([*unpacked[1:9], *self._channels[8:]])

    def _handle_param_value(self, payload: bytes) -> None:
        if len(payload) < 25:
            return
        value, _count, _index, raw_id, _param_type = struct.unpack_from("<fHH16sB", payload, 0)
        param_id = raw_id.split(b"\x00", 1)[0].decode("ascii", errors="ignore").strip()
        if not param_id or not any(keyword in param_id.upper() for keyword in PID_PARAM_KEYWORDS):
            return
        self._pid_params[param_id] = value
        self._telemetry_dirty = True

    def _handle_pid_tuning(self, payload: bytes) -> None:
        if len(payload) < 25:
            return
        axis, desired, achieved, p, i, d, ff = struct.unpack_from("<B6f", payload, 0)
        self._tuning_frames += 1
        self._pid_tuning[axis] = (p, i, d, ff, desired, achieved)
        self._telemetry_dirty = True

    def _update_channels(self, channels: list[int]) -> None:
        self._channels = channels[:RC_CHANNEL_COUNT]
        self._telemetry_dirty = True
        now = time.monotonic()
        if now - self._last_channel_log >= 0.5:
            self._last_channel_log = now
            values = " ".join(str(value) for value in self._channels)
            self._write_log(f"CH {datetime.now().isoformat(timespec='milliseconds')} {values}\n")

    def _refresh_telemetry(self) -> None:
        if self._telemetry_dirty:
            self._telemetry_dirty = False
            for index, value in enumerate(self._channels):
                self._channel_vars[index].set(str(value) if value else "--")
                self._channel_bars[index].configure(value=value)
            self.telemetry_summary.set(
                f"RC_CHANNELS 帧: {self._rc_frames}    PID_TUNING 帧: {self._tuning_frames}    "
                f"PID 参数: {len(self._pid_params)}"
            )
            self._refresh_pid_tables()
        self.root.after(100, self._refresh_telemetry)

    def _refresh_pid_tables(self) -> None:
        for name, value in sorted(self._pid_params.items()):
            text = f"{value:.6g}"
            row = self._pid_param_rows.get(name)
            if row is None:
                self._pid_param_rows[name] = self.pid_param_tree.insert("", "end", values=(name, text))
            else:
                self.pid_param_tree.item(row, values=(name, text))
        for axis, values in sorted(self._pid_tuning.items()):
            p, i, d, ff, desired, achieved = values
            row_values = (
                PID_TUNING_AXES.get(axis, f"轴{axis}"),
                f"{p:.4g}",
                f"{i:.4g}",
                f"{d:.4g}",
                f"{ff:.4g}",
                f"{desired:.4g}",
                f"{achieved:.4g}",
            )
            row = self._pid_tuning_rows.get(axis)
            if row is None:
                self._pid_tuning_rows[axis] = self.pid_tuning_tree.insert("", "end", values=row_values)
            else:
                self.pid_tuning_tree.item(row, values=row_values)

    def _choose_log_dir(self) -> None:
        selected = filedialog.askdirectory(initialdir=self.log_dir.get())
        if selected:
            self.log_dir.set(selected)

    def _start(self) -> None:
        try:
            connect_port = int(self.connect_port.get())
            listen_port = int(self.listen_port.get())
            if not all(1 <= port <= 65535 for port in (connect_port, listen_port)):
                raise ValueError
            socket.gethostbyname(self.remote_ip.get().strip())
        except (ValueError, socket.gaierror):
            messagebox.showerror("连接设置错误", "请填写有效的 IP 地址和连接端口。")
            return
        try:
            Path(self.log_dir.get()).mkdir(parents=True, exist_ok=True)
            self._socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self._socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self._socket.bind(("0.0.0.0", listen_port))
            self._socket.settimeout(0.5)
            self._started_at = datetime.now().strftime("%Y%m%d_%H%M%S")
            log_path = Path(self.log_dir.get()) / f"mavlink_debug_{self._started_at}.txt"
            self._log_file = log_path.open("w", encoding="utf-8", newline="\n")
            self._write_log(f"会话开始 UTC={datetime.now(timezone.utc).isoformat()}\n")
            self._write_log(
                f"remote={self.remote_ip.get()} pairing_port={self.pairing_port.get()} "
                f"connect_port={connect_port} listen=0.0.0.0:{listen_port}\n"
            )
            self._write_log("pair_protocol=android-adb-wireless-debug; raw MAVLink payloads are preserved\n")
            self._stop.clear()
            self._packets = 0
            self._bytes = 0
            self._worker = threading.Thread(target=self._receive_loop, daemon=True)
            self._worker.start()
            if not self._connect_device(connect_port):
                self._stop_capture()
                return
            self.status.set(f"监听中，日志: {log_path.name}")
            self.start_button.configure(state="disabled")
            self.stop_button.configure(state="normal")
        except OSError as error:
            self._cleanup_socket()
            messagebox.showerror("启动失败", f"无法监听端口或创建日志：\n{error}")

    def _pair_only(self) -> None:
        try:
            pairing_port = int(self.pairing_port.get())
            if not 1 <= pairing_port <= 65535:
                raise ValueError
            socket.gethostbyname(self.remote_ip.get().strip())
            if not self.pair_code.get().strip().isdigit() or len(self.pair_code.get().strip()) != 6:
                raise ValueError
        except (ValueError, socket.gaierror):
            messagebox.showerror("配对设置错误", "请填写有效的 IP、配对端口和 6 位配对码。")
            return
        adb = self._find_adb()
        if not adb:
            self._append_output("未找到 adb.exe，请安装 Android SDK Platform Tools。\n")
            return
        output = self._run_adb(adb, ["pair", f"{self.remote_ip.get().strip()}:{pairing_port}"], self.pair_code.get().strip())
        self._append_output(f"ADB 配对结果：\n{output}\n")
        if "successfully paired" not in output.lower():
            self._append_output("配对失败：请确认 G12 仍停留在‘使用配对码配对设备’页面。\n")
            return
        self._paired = True
        self.connect_port_entry.configure(state="normal")
        self.start_button.configure(state="normal")
        self.pair_button.configure(state="disabled")
        self.status.set("配对成功，请填写连接端口")

    def _connect_device(self, connect_port: int) -> bool:
        adb = self._find_adb()
        if not adb:
            self._append_output("未找到 adb.exe，请安装 Android SDK Platform Tools。\n")
            self._write_log("ADB_ERROR adb.exe not found\n")
            return False
        connect_endpoint = f"{self.remote_ip.get().strip()}:{connect_port}"
        output = self._run_adb(adb, ["connect", connect_endpoint])
        self._write_log(f"ADB_CONNECT {datetime.now().isoformat()}\n{output}\n")
        self._append_output(f"ADB 连接结果：\n{output}\n")
        connected = "connected to" in output.lower() or "already connected" in output.lower()
        if not connected:
            self._append_output("ADB 连接失败：请在 G12 无线调试主页面读取连接端口后重试。\n")
        return connected

    @staticmethod
    def _find_adb() -> str | None:
        candidates = [
            shutil.which("adb"),
            r"D:\study_sofeware\SDK\platform-tools\adb.exe",
            r"D:\study_sofeware\Android\Sdk\platform-tools\adb.exe",
        ]
        return next((path for path in candidates if path and Path(path).exists()), None)

    @staticmethod
    def _run_adb(adb: str, arguments: list[str], stdin_text: str = "") -> str:
        try:
            result = subprocess.run(
                [adb, *arguments], input=f"{stdin_text}\n" if stdin_text else None,
                capture_output=True, text=True, timeout=15, check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            return f"ADB 执行错误: {error}"
        return (result.stdout + result.stderr).strip()

    def _receive_loop(self) -> None:
        while not self._stop.is_set():
            try:
                payload, address = self._socket.recvfrom(65535) if self._socket else (b"", ("", 0))
            except socket.timeout:
                continue
            except OSError:
                break
            timestamp = datetime.now().isoformat(timespec="milliseconds")
            self._packets += 1
            self._bytes += len(payload)
            mavlink_hint = self._mavlink_hint(payload)
            line = f"RX {timestamp} from={address[0]}:{address[1]} len={len(payload)} {mavlink_hint} hex={payload.hex(' ')}\n"
            self._write_log(line)
            self._events.put(("packet", line, payload))

    @staticmethod
    def _mavlink_hint(payload: bytes) -> str:
        if not payload:
            return "empty"
        if payload[0] == 0xFE and len(payload) >= 6:
            return f"MAVLink-v1 msgid={payload[5]} seq={payload[2]}"
        if payload[0] == 0xFD and len(payload) >= 10:
            message_id = payload[7] | (payload[8] << 8) | (payload[9] << 16)
            return f"MAVLink-v2 msgid={message_id} seq={payload[4]}"
        return "non-MAVLink-or-fragment"

    def _write_log(self, text: str) -> None:
        if self._log_file:
            self._log_file.write(text)
            self._log_file.flush()

    def _append_output(self, text: str) -> None:
        self.output.configure(state="normal")
        if float(self.output.index("end-1c").split(".")[0]) > 2000:
            self.output.delete("1.0", "500.0")
        self.output.insert("end", text)
        self.output.see("end")
        self.output.configure(state="disabled")

    def _drain_events(self) -> None:
        while True:
            try:
                kind, text, payload = self._events.get_nowait()
            except queue.Empty:
                break
            if kind == "packet":
                self._append_output(text)
                self.packet_count.set(f"数据包: {self._packets}    字节: {self._bytes}")
                self._process_mavlink(payload)
        self.root.after(100, self._drain_events)

    def _stop_capture(self) -> None:
        self._stop.set()
        self._cleanup_socket()
        if self._log_file:
            self._write_log(f"会话结束 packets={self._packets} bytes={self._bytes}\n")
            self._log_file.close()
            self._log_file = None
        self.status.set("已停止")
        self.start_button.configure(state="normal")
        self.stop_button.configure(state="disabled")

    def _cleanup_socket(self) -> None:
        if self._socket:
            try:
                self._socket.close()
            except OSError:
                pass
            self._socket = None

    def _close(self) -> None:
        self._stop_capture()
        self.root.destroy()


def main() -> None:
    root = tk.Tk()
    WirelessDebugAssistant(root)
    root.mainloop()


if __name__ == "__main__":
    main()
