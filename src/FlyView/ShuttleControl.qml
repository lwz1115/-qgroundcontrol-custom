import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// 两点穿梭横移（OMNI X 船形专属）：左下角横移图标，点击展开面板。
///
/// 面板：
///   - 航点 A / 航点 B 下拉：从当前任务航点中选择（A 默认第一、B 默认最后一个）
///   - 每个航点的“到点动作”下拉：无动作（悬停）/ 延迟 N 秒（默认 10s，可输入）
///   - 按钮：切换（A↔B 往返）/ 停止（退出穿梭，船悬停）
///   - 状态显示：当前在 A / 在 B / 移动中 / 执行任务中
///
/// 状态机完全在 QML 持有（Vehicle 只负责发 DO_REPOSITION 与透传飞控消息）：
///   Idle → MovingToA/B → HoverAtA/B → TaskAtA/B → HoverAtA/B → … → Idle
/// 到点判定 = 位置距离 ≤ 阈值 且 地速 < 阈值（双条件），REACHED_WP 作辅助确认。
/// 手动接管（MANUAL_MODE_OVERRIDE 或飞行模式变化）立即退出穿梭。
Item {
    id: control

    // 用于直接读写飞控 WP_SPEED 参数（穿梭速度以飞控为准，与速度面板一致）
    FactPanelController {
        id: shuttleFacts
    }

    /// 上层传下来的可用区域（与水质/采样卡片同一套坐标系）
    property var parentToolInsets
    /// 摄像头小窗左上角与宽度，由 FlyViewCustomLayer 提供
    property point pipTopLeft
    property real  pipWidth: 0

    readonly property real _margin:       ScreenTools.defaultFontPixelWidth * 0.75
    /// 卡片边长：与采样卡完全一致（随小窗宽度联动 + 封顶），保证三卡竖排严格对齐
    readonly property real _cardSize:     (_camActive && pipWidth > 0)
                                          ? Math.min(pipWidth * 0.28, ScreenTools.defaultFontPixelHeight * 1.9)
                                          : ScreenTools.defaultFontPixelHeight * 1.7
    readonly property real _spacing:      ScreenTools.defaultFontPixelWidth * 0.25
    readonly property real _pipClearance: ScreenTools.defaultFontPixelWidth * 0.75
    readonly property real _iconX:        control.pipTopLeft.x

    // 横移卡在采样卡上方，形成“横移 / 采样 / 水质”竖排；用 Math.max 兜底，
    // 避免小窗靠顶时三卡被推出屏幕外（采样/水质只算两卡，横移更高一格更容易溢出）。
    readonly property real _iconsTopY: control._camActive
                                        ? Math.max(0, control.pipTopLeft.y - control._cardSize * 3 - control._spacing * 2 - control._pipClearance)
                                        : Math.max(0, parent.height - control._cardSize * 3 - control._spacing * 2 - control._margin)

    /// 摄像头是否在显示（决定卡片贴小窗顶还是落左下角）
    readonly property bool _camActive: QGroundControl.videoManager.isStreamSource
                                        || QGroundControl.videoManager.isUvc

    /// 当前活动载具 / OMNI X 显示条件
    readonly property var  _activeVehicle:    QGroundControl.multiVehicleManager.activeVehicle
    readonly property bool _vehicleConnected: !!_activeVehicle
    readonly property bool _isOmniX:          _activeVehicle ? _activeVehicle.isOmniX : false

    // ---- 航点下拉数据源：飞行界面的任务（已上传/下载生效的那份）----
    readonly property var _flyMissionController: {
        const planController = globals.planMasterControllerFlyView
        return planController ? planController.missionController : null
    }
    readonly property var _waypointItems: {
        // 收集任务里所有带坐标的航点（跳过 home 设置项 index 0）
        const mc = control._flyMissionController
        const result = []
        if (!mc || !mc.visualItems) {
            return result
        }
        for (let i = 1; i < mc.visualItems.count; i++) {
            const item = mc.visualItems.get(i)
            if (item && item.specifiesCoordinate && !item.isStandaloneCoordinate
                    && item.coordinate && item.coordinate.isValid) {
                result.push({ text: qsTr("航点 %1").arg(item.missionItemNumber > 0 ? item.missionItemNumber : item.sequenceNumber),
                              coord: item.coordinate })
            }
        }
        return result
    }

    // ---- 穿梭状态机（QML 持有）----
    property int    _state:     0   ///< 0=Idle 1=MovingToA 2=MovingToB 3=HoverAtA 4=HoverAtB 5=TaskAtA 6=TaskAtB
    property int    _currentAt: -1  ///< 当前所在点：0=A 1=B -1=未启动
    property int    _targetAt:  -1  ///< 正在前往的目标点
    property bool   _taskActive: false  ///< 任务执行中（延迟计时），不可通过 UI 取消
    property real   _taskRemain: 0     ///< 任务剩余秒数
    property string _hintText:   ""    ///< 提示文案（飞控消息 / 本地提示）

    // 航点 A / B 选择（默认 A=第一个，B=最后一个）
    property int _selectedA: 0
    property int _selectedB: _waypointItems.length > 1 ? _waypointItems.length - 1 : 0

    /// 航点 A / B 坐标
    readonly property var _coordA: control._waypointItems.length > control._selectedA ? control._waypointItems[control._selectedA].coord : null
    readonly property var _coordB: control._waypointItems.length > control._selectedB ? control._waypointItems[control._selectedB].coord : null

    /// 到点动作（0=无动作，1=延迟秒数）
    property int    _actionA: 1
    property int    _actionB: 1
    property real   _delayA:  10
    property real   _delayB:  10

    /// 距离限制（最小 0.5m / 最大 5000m）
    readonly property real _minDist: 0.5
    readonly property real _maxDist: 5000.0
    readonly property real _abDistance: {
        if (!control._coordA || !control._coordB || !control._coordA.isValid || !control._coordB.isValid) {
            return -1
        }
        const d = control._coordA.distanceTo(control._coordB)
        return isNaN(d) ? -1 : d
    }
    readonly property bool _distOk: control._abDistance >= control._minDist && control._abDistance <= control._maxDist

    /// 到点阈值：距离 ≤ 1.0m 且 地速 < 0.2m/s（与飞控 SHUTTLE_RAD / SHUTTLE_SPD 一致）
    readonly property real _arriveDistM: 1.0
    readonly property real _arriveSpeed: 0.2

    /// 面板宽度
    readonly property real _popupWidth: {
        const maxWidth = Math.max(ScreenTools.defaultFontPixelWidth * 14, width - _margin * 4)
        return Math.min(ScreenTools.defaultFontPixelWidth * 42, maxWidth)
    }

    /// 当前状态文案
    readonly property string _stateText: {
        switch (control._state) {
        case 1: return qsTr("移动中：前往 A 点")
        case 2: return qsTr("移动中：前往 B 点")
        case 3: return qsTr("悬停在 A 点")
        case 4: return qsTr("悬停在 B 点")
        case 5: return qsTr("A 点任务执行中…")
        case 6: return qsTr("B 点任务执行中…")
        default: return qsTr("穿梭未启动")
        }
    }

    /// 按钮文案
    readonly property string _switchText: {
        if (control._state === 1 || control._state === 2) return qsTr("移动中…")
        if (control._state === 5 || control._state === 6) return qsTr("任务执行中…")
        return control._currentAt === 0 ? qsTr("切换 → B") : qsTr("切换 → A")
    }

    // ---- 状态机驱动 ----

    /// 每 500ms 检查到点：距离 ≤ 阈值 且 地速 < 阈值
    function _checkArrival() {
        if (control._state !== 1 && control._state !== 2) {
            return
        }
        const vehicle = control._activeVehicle
        if (!vehicle) {
            return
        }
        const target = control._targetAt === 0 ? control._coordA : control._coordB
        if (!target || !target.isValid || !vehicle.coordinate || !vehicle.coordinate.isValid) {
            return
        }
        const dist = vehicle.coordinate.distanceTo(target)
        const speed = vehicle.vehicle && vehicle.vehicle.groundSpeed ? vehicle.vehicle.groundSpeed.value : 999
        if (!isNaN(dist) && dist <= control._arriveDistM && speed < control._arriveSpeed) {
            control._onArrived()
        }
    }

    /// 到达目标点：进入悬停；若该点配置了任务，进入任务阶段（延迟计时）
    function _onArrived() {
        const at = control._targetAt
        control._currentAt = at
        control._targetAt = -1
        const delay = at === 0 ? control._delayA : control._delayB
        const hasTask = (at === 0 ? control._actionA : control._actionB) === 1
        if (hasTask && delay > 0) {
            control._state = at === 0 ? 5 : 6
            control._taskActive = true
            control._taskRemain = delay
            taskTimer.start()
        } else {
            control._state = at === 0 ? 3 : 4
            control._taskActive = false
            control._hintText = ""
        }
    }

    /// 用户点「切换」：从当前点飞往另一航点
    function _onSwitch() {
        if (!control._vehicleConnected || !control._isOmniX) {
            return
        }
        // 任务执行中不可取消（UI 层禁止）
        if (control._taskActive) {
            return
        }
        if (!control._distOk) {
            control._hintText = control._abDistance < 0
                    ? qsTr("航点坐标无效")
                    : (control._abDistance < control._minDist
                            ? qsTr("两点距离过近（< 0.5m）")
                            : qsTr("两点距离过远（> 5000m）"))
            return
        }
        // 决定目标点：当前在 A 或去 A → 去 B；否则去 A
        const goTo = (control._currentAt === 0 || control._targetAt === 0) ? 1 : 0
        control._startMove(goTo)
    }

    /// 开始前往目标点
    function _startMove(goTo) {
        const coord = goTo === 0 ? control._coordA : control._coordB
        if (!coord || !coord.isValid) {
            control._hintText = qsTr("目标航点无效")
            return
        }
        // 速度：优先用飞控 WP_SPEED 参数（与速度面板一致，以飞控为准）；
        // 参数尚未就绪时回退本地记忆 autonomousNavSpeed（默认 1 m/s）。
        let speed = 1.0
        const wpSpeedFact = shuttleFacts.getParameterFact(-1, "WP_SPEED", false)
        if (wpSpeedFact) {
            const v = Number(wpSpeedFact.value)
            speed = v > 0 ? v : speed
        } else {
            const mem = Number(QGroundControl.settingsManager.appSettings.autonomousNavSpeed.value)
            speed = mem > 0 ? mem : speed
        }
        const ok = control._activeVehicle.startShuttle(coord.latitude, coord.longitude, speed, control._arriveDistM)
        if (!ok) {
            control._hintText = qsTr("启动穿梭失败")
            return
        }
        control._targetAt = goTo
        control._state = goTo === 0 ? 1 : 2
        control._taskActive = false
        control._hintText = ""
    }

    /// 用户点「停止」：任务中禁用；否则退出穿梭并切 LOITER 悬停
    function _onStop() {
        if (control._taskActive) {
            // 任务执行中不可通过 UI 取消（飞控切手动仍可接管）
            return
        }
        control._exitShuttle()
    }

    /// 退出穿梭：复位状态机 + 切 LOITER 悬停
    function _exitShuttle() {
        taskTimer.stop()
        control._state = 0
        control._currentAt = -1
        control._targetAt = -1
        control._taskActive = false
        control._taskRemain = 0
        control._hintText = ""
        // 切 LOITER 让船悬停（Rover 只有 HOLD/LOITER，飞控要求 LOITER）
        if (control._vehicleConnected && control._activeVehicle.flightMode
                && control._activeVehicle.flightMode.toLowerCase().indexOf("loiter") < 0) {
            control._activeVehicle.flightMode = "Loiter"
        }
    }

    // ---- 飞控消息 / 手动接管 ----
    Connections {
        target: control._activeVehicle

        function onShuttleMessageChanged() {
            const msg = control._activeVehicle.shuttleMessage
            if (!msg) {
                return
            }
            // 手动接管：立即退出穿梭（安全优先）
            if (msg.indexOf("MANUAL_MODE_OVERRIDE") >= 0) {
                control._exitShuttle()
                control._hintText = qsTr("手动模式接管，穿梭已退出")
                return
            }
            // 到点辅助确认：若正在移动中，直接按已到点处理
            if (msg.indexOf("REACHED_WP") >= 0) {
                if (control._state === 1 || control._state === 2) {
                    control._onArrived()
                }
                return
            }
            // 任务结束：回到悬停
            if (msg.indexOf("SHUTTLE_TASK_END") >= 0 || msg.indexOf("TASK_DONE") >= 0) {
                if (control._state === 5 || control._state === 6) {
                    taskTimer.stop()
                    control._taskActive = false
                    control._state = control._currentAt === 0 ? 3 : 4
                }
                return
            }
            // 距离超限 / 其它：显示提示
            if (msg.indexOf("SHUTTLE_ERR_DIST") >= 0 || msg.indexOf("SHUTTLE_TASK_START") >= 0 || msg.indexOf("SHUTTLE_STATE") >= 0) {
                control._hintText = msg
            }
        }

        function onFlightModeChanged() {
            // 非穿梭期间切手动不处理；穿梭中一旦离开 LOITER/AUTO 视为接管，立即退出
            if (control._state === 0) {
                return
            }
            const mode = control._activeVehicle ? control._activeVehicle.flightMode : ""
            const lower = mode.toLowerCase()
            if (lower.indexOf("manual") >= 0 || lower.indexOf("rc") >= 0 || lower.indexOf("stabilize") >= 0) {
                control._exitShuttle()
                control._hintText = qsTr("手动模式接管，穿梭已退出")
            }
        }
    }

    /// 到点检查定时器
    Timer {
        id: arrivalTimer
        interval: 500
        repeat: true
        running: control._state === 1 || control._state === 2
        onTriggered: control._checkArrival()
    }

    /// 任务（延迟 N 秒）计时
    Timer {
        id: taskTimer
        interval: 1000
        repeat: true
        onTriggered: {
            control._taskRemain -= 1
            if (control._taskRemain <= 0) {
                // 任务结束：回到悬停，等待用户切换
                control._taskActive = false
                control._state = control._currentAt === 0 ? 3 : 4
                taskTimer.stop()
            }
        }
    }

    // ------------------------------------------------------------------
    // 左下角横移图标（方形卡片，与水质/采样同风格，位于采样卡上方）
    // ------------------------------------------------------------------
    Rectangle {
        id: iconButton

        x:              control._iconX
        y:              control._iconsTopY
        width:          control._cardSize
        height:         control._cardSize
        radius:         ScreenTools.defaultBorderRadius
        color:          Qt.rgba(0, 0, 0, 0.6)
        border.color:   Qt.rgba(1, 1, 1, iconMouseArea.containsMouse ? 0.75 : 0.35)
        border.width:   1
        visible:        control._isOmniX && control._vehicleConnected

        QGCColoredImage {
            anchors.centerIn: parent
            width:            parent.width * 0.58
            height:           parent.height * 0.58
            source:           "/res/shuttle.svg"
            color:            "white"
        }

        MouseArea {
            id:           iconMouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked:    controlPopup.visible ? controlPopup.close() : controlPopup.open()
        }
    }

    // ------------------------------------------------------------------
    // 穿梭控制面板
    // ------------------------------------------------------------------
    Popup {
        id:             controlPopup
        x:              iconButton.x
        y:              Math.max(control._margin, iconButton.y - implicitHeight - control._margin)
        width:          control._popupWidth
        padding:        control._margin
        closePolicy:    Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color:        Qt.rgba(0, 0, 0, 0.85)
            border.color: Qt.rgba(1, 1, 1, 0.25)
            border.width: 1
            radius:       ScreenTools.defaultBorderRadius
        }

        contentItem: ColumnLayout {
            spacing: control._margin

            QGCLabel {
                Layout.fillWidth: true
                text:             qsTr("两点穿梭横移")
                color:            "white"
                font.bold:        true
            }

            // ---- 航点 A ----
            QGCLabel {
                text:  qsTr("航点 A")
                color: Qt.rgba(1, 1, 1, 0.7)
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: control._margin
                QGCComboBox {
                    id: comboA
                    Layout.fillWidth: true
                    model: {
                        const names = []
                        for (let i = 0; i < control._waypointItems.length; i++) {
                            names.push(control._waypointItems[i].text)
                        }
                        return names
                    }
                    currentIndex: control._selectedA
                    onActivated: (index) => { control._selectedA = index }
                }
                QGCComboBox {
                    id: actionA
                    model: [qsTr("无动作（悬停）"), qsTr("延迟 %1 秒").arg(control._delayA)]
                    currentIndex: control._actionA
                    onActivated: (index) => { control._actionA = index }
                }
            }

            // ---- 航点 B ----
            QGCLabel {
                text:  qsTr("航点 B")
                color: Qt.rgba(1, 1, 1, 0.7)
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: control._margin
                QGCComboBox {
                    id: comboB
                    Layout.fillWidth: true
                    model: comboA.model
                    currentIndex: control._selectedB
                    onActivated: (index) => { control._selectedB = index }
                }
                QGCComboBox {
                    id: actionB
                    model: [qsTr("无动作（悬停）"), qsTr("延迟 %1 秒").arg(control._delayB)]
                    currentIndex: control._actionB
                    onActivated: (index) => { control._actionB = index }
                }
            }

            // ---- 延迟秒数输入（可编辑）----
            RowLayout {
                Layout.fillWidth: true
                visible: control._actionA === 1 || control._actionB === 1
                QGCLabel { text: qsTr("延迟秒数") }
                QGCTextField {
                    Layout.fillWidth: true
                    text: String(control._delayA)
                    onEditingFinished: {
                        const v = parseFloat(text)
                        if (!isNaN(v) && v >= 0) {
                            control._delayA = v
                            control._delayB = v
                        }
                    }
                }
            }

            // ---- 状态与提示 ----
            QGCLabel {
                Layout.fillWidth: true
                text:             control._stateText
                color:            "white"
                font.bold:        control._state !== 0
            }
            QGCLabel {
                Layout.fillWidth: true
                visible:          control._taskActive
                text:             qsTr("任务剩余：%1 秒").arg(Math.max(0, Math.round(control._taskRemain)))
                color:            "white"
            }
            QGCLabel {
                Layout.fillWidth: true
                visible:          control._hintText !== ""
                text:             control._hintText
                color:            "#F5A623"
                wrapMode:         Text.WordWrap
            }
            QGCLabel {
                Layout.fillWidth: true
                visible:          !control._distOk && control._coordA && control._coordB
                text:             control._abDistance < control._minDist
                                    ? qsTr("两点距离过近（< 0.5m），无法切换")
                                    : qsTr("两点距离过远（> 5000m），无法切换")
                color:            "#F5A623"
                wrapMode:         Text.WordWrap
            }

            // ---- 切换 / 停止 ----
            RowLayout {
                Layout.fillWidth: true
                spacing: control._margin

                QGCButton {
                    Layout.fillWidth: true
                    text:                control._switchText
                    enabled:             control._vehicleConnected && control._isOmniX
                                          && !control._taskActive
                                          && (control._state === 0 || control._state === 3 || control._state === 4)
                                          && control._distOk
                    onClicked:           control._onSwitch()
                }

                QGCButton {
                    Layout.fillWidth: true
                    text:                qsTr("停止")
                    enabled:             control._state !== 0 && !control._taskActive
                    onClicked:           control._onStop()
                }
            }
        }
    }
}
