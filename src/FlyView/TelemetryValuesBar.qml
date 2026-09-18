import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

Item {
    id:             control
    implicitWidth:  mainLayout.width + (_toolsMargin * 2)
    implicitHeight: mainLayout.height + (_toolsMargin * 2)

    property real extraWidth: 0 ///< Extra width to add to the background rectangle

    property var specificVehicleForCard: null

    readonly property real _toolsMargin: ScreenTools.defaultFontPixelWidth * 0.75

    property date _currentTime: new Date()
    property var _vehicle: specificVehicleForCard ? specificVehicleForCard : QGroundControl.multiVehicleManager.activeVehicle
    property var _battery: _vehicle && _vehicle.batteries && _vehicle.batteries.count > 0 ? _vehicle.batteries.get(0) : null

    readonly property string _dateText:         Qt.formatDate(_currentTime, "yyyy-MM-dd")
    readonly property string _timeText:         Qt.formatTime(_currentTime, "HH:mm:ss")
    readonly property string _sessionTimeText:  _formatDuration(_currentTime.getTime() - globals.appStartTime.getTime())
    readonly property string _speedText:        _vehicle && _vehicle.vehicle.groundSpeed ? _vehicle.vehicle.groundSpeed.valueString + " " + _vehicle.vehicle.groundSpeed.units : "--"
    readonly property string _latitudeText:     _vehicle ? _vehicle.latitude.toFixed(6) : "--"
    readonly property string _longitudeText:    _vehicle ? _vehicle.longitude.toFixed(6) : "--"
    readonly property string _voltageText:      _battery && _battery.voltage ? _battery.voltage.valueString + " " + _battery.voltage.units : "--"

    // 计数用的控制器：飞行视图那份，实时跟踪载具 MISSION_CURRENT（规划视图那份只跟编辑内容，不能用来算圈）
    readonly property var _flyMissionController: {
        const planController = globals.planMasterControllerFlyView
        return planController ? planController.missionController : null
    }

    // 总圈数只看“已上传生效”的那份：飞行界面控制器里的任务（上传/下载后会刷成船上的值），
    // 规划界面里改了但没上传的循环次数不参与显示
    readonly property var _missionLoopCount: {
        const missionController = control._flyMissionController
        if (!missionController || missionController.visualItems.count === 0) {
            return null
        }
        const settingsItem = missionController.visualItems.get(0)
        return (settingsItem && settingsItem.loopCount) ? settingsItem.loopCount.rawValue : null
    }

    // 起点序号（DO_JUMP 的回跳目标，即第一个航点）：航点不足 2 项时无法判圈，返回 -1
    readonly property int _loopStartIndex: {
        const items = control._flyMissionController ? control._flyMissionController.visualItems : null
        if (!items || items.count < 2) {
            return -1
        }
        const firstWaypoint = items.get(1)
        return firstWaypoint ? firstWaypoint.sequenceNumber : -1
    }

    // 终点序号：任务里最后一个“航点”的序号（specifiesCoordinate 为 true）。
    // 任务末尾的 DO_JUMP 是动作项、没有坐标，必须排除，否则永远等不到终点。
    readonly property int _loopEndIndex: {
        const items = control._flyMissionController ? control._flyMissionController.visualItems : null
        if (!items || items.count < 2) {
            return -1
        }
        let endIndex = -1
        for (let i = 0; i < items.count; i++) {
            const item = items.get(i)
            if (item && item.specifiesCoordinate) {
                endIndex = item.sequenceNumber
            }
        }
        return endIndex
    }

    property int    _completedLoops:   0      ///< 已完成的圈数：离开终点（或停在终点判定完成）才算一圈
    property int    _lastMissionIndex: -1     ///< 上一次的 MISSION_CURRENT 序号
    property bool   _loopRunActive:    false  ///< 本趟是否已起步：起步后才允许计圈
    property bool   _atLoopEnd:        false  ///< 正停在终点（到达但还没离开，不算完成）
    property bool   _taskCompleted:    false  ///< 本趟任务已跑满总圈数并停止
    property string _loopMissionKey:   ""     ///< 本趟任务的特征（起点/终点/总圈数），用来识别“任务是否被替换”

    /// 总圈数（船上已生效值），可能为 null（拿不到就不做完成判定）
    readonly property var _totalLoops: control._missionLoopCount

    /// 任务完成判定超时：到达终点后序号长时间不变，就认为“船已停在终点、任务结束”
    readonly property int _taskCompleteDetectTimeoutMs: 8000

    /// 任务运行中：已解锁 + 处于任务模式（与 MissionController::sendToVehiclePreCheck 的判定一致）
    readonly property bool _missionRunning: {
        const vehicle = control._vehicle
        return vehicle ? (vehicle.armed && (vehicle.flightMode === vehicle.missionFlightMode)) : false
    }

    // 显示“已循环次数/总次数”，例如 3/5；拿不到总次数时显示 “--”
    readonly property string _loopCountText: _missionLoopCount === null ? "--" : (_completedLoops + "/" + _missionLoopCount)

    /// 任务特征：起点/终点/总圈数一致就认为是同一个任务
    function _loopMissionKeyOf() {
        return control._loopStartIndex + ":" + control._loopEndIndex + ":" + control._missionLoopCount
    }

    /// 把“任务运行中/已完成”写回飞行界面的任务控制器，供规划界面拦截“任务执行中改航线/上传”。
    /// 只在主遥测栏写（多机卡片不写），避免多机时相互覆盖。
    function _publishTaskState() {
        if (specificVehicleForCard) {
            return
        }
        const planController = globals.planMasterControllerFlyView
        if (planController) {
            planController.missionTaskRunning = control._missionRunning
            planController.missionTaskCompleted = control._taskCompleted
        }
    }

    // 回到“本趟还没起步”的状态，计数清零
    function _resetLoopProgress() {
        _completedLoops = 0
        _lastMissionIndex = -1
        _loopRunActive = false
        _atLoopEnd = false
        _taskCompleted = false
        _loopMissionKey = control._loopMissionKeyOf()
        completeDetectTimer.stop()
        control._publishTaskState()
    }

    // 计圈规则（MISSION_CURRENT 是“开始前往该航点”时上报，不是“到达”时上报）：
    //   a) 起步：本趟未起步且序号已进入任务范围 → 清零重计
    //   b) 新一趟：本趟已完成、又回到起点 → 清零重计
    //   c) 到达终点：只标记“正停在终点”，并启动完成判定定时器，此时不 +1
    //   d) 离开终点：这一圈才算完成 → +1；跑满总圈数则标记任务已完成
    //   e) 其余只记录上一次序号；总圈数未知时不做完成判定，只按 d) 计圈
    function _updateLoopProgress(missionIndex) {
        if ((_loopStartIndex < 0) || (_loopEndIndex < _loopStartIndex)) {
            return
        }

        if (!_loopRunActive) {
            if (missionIndex >= _loopStartIndex) {
                _resetLoopProgress()
                _loopRunActive = true
                control._publishTaskState()
            }
        } else if (_taskCompleted && (missionIndex === _loopStartIndex)) {
            _resetLoopProgress()
            _loopRunActive = true
            control._publishTaskState()
        } else if (!_atLoopEnd && (missionIndex === _loopEndIndex)) {
            _atLoopEnd = true
            if (_totalLoops !== null) {
                completeDetectTimer.restart()
            }
        } else if (_atLoopEnd && (missionIndex !== _loopEndIndex)) {
            completeDetectTimer.stop()
            _atLoopEnd = false
            _completedLoops++
            if ((_totalLoops !== null) && (_completedLoops >= _totalLoops)) {
                _taskCompleted = true
                control._publishTaskState()
            }
        }

        _lastMissionIndex = missionIndex
    }

    // 到达终点后序号一直不变 → 判定“船已停在终点、任务结束”，补上最后一圈。
    // 只是一次性的完成检测，不是周期轮询任务，也不触发任何上传。
    // 注：停船由飞控处理（循环次数用尽后不再跳回、任务结束）；若某些固件需要 QGC 主动下发
    // HOLD/暂停命令，可在这个函数里补（飞控端需配合上报 COMPLETED）。
    function _handleTaskCompleteDetected() {
        if (!_loopRunActive || !_atLoopEnd) {
            return
        }
        if ((_totalLoops !== null) && (_completedLoops < _totalLoops)) {
            _completedLoops++
        }
        _atLoopEnd = false
        _taskCompleted = true
        control._publishTaskState()
    }

    Timer {
        id: completeDetectTimer
        interval: control._taskCompleteDetectTimeoutMs
    }

    // 解锁/飞行模式变化时同步“任务运行中”状态（用于拦截任务执行中改航线/上传）
    on_MissionRunningChanged: control._publishTaskState()

    // 只有“任务被替换”才清零：重连/重新下载同一个任务时 visualItems 也会重建，
    // 但起点/终点/总圈数不变，已跑圈数保留（任务执行中上传也不清零）；
    // 也刻意不在载具上锁时清零，否则“停到终点”后看不到 2/2。
    Connections {
        target: control._flyMissionController

        function onCurrentMissionIndexChanged(missionIndex) {
            control._updateLoopProgress(missionIndex)
        }
        function onVisualItemsReset() {
            // 等绑定刷新到新任务的值以后再比较任务特征
            Qt.callLater(control._checkMissionReplaced)
        }
    }

    /// 任务被替换后：起点/终点/总圈数变了才清零，同一个任务（重连、重下载）保持已跑圈数
    function _checkMissionReplaced() {
        const missionKey = control._loopMissionKeyOf()
        if (missionKey !== control._loopMissionKey) {
            control._resetLoopProgress()
        }
    }

    readonly property real _labelWidth: labelFontMetrics.widestLabelWidth
    // 值列只是“最短宽度”：内容更长时列会自己撑开，不会裁剪，也不会把字体拉伸变形
    readonly property real _valueWidth: ScreenTools.defaultFontPixelWidth * 8

    function _formatDuration(milliseconds) {
        const totalSeconds = Math.max(0, Math.floor(milliseconds / 1000))
        const seconds = totalSeconds % 60
        const minutes = Math.floor(totalSeconds / 60) % 60
        const hours = Math.floor(totalSeconds / 3600)
        return _twoDigits(hours) + ":" + _twoDigits(minutes) + ":" + _twoDigits(seconds)
    }

    function _twoDigits(value) {
        return value < 10 ? "0" + value : String(value)
    }

    Timer {
        interval:         1000
        repeat:           true
        triggeredOnStart: true
        running:          control.visible
        onTriggered:      control._currentTime = new Date()
    }

    /// Label column width, so the trailing colons line up across all rows in every language.
    FontMetrics {
        id: labelFontMetrics

        font.pointSize: ScreenTools.defaultFontPointSize
        font.family:    ScreenTools.normalFontFamily

        readonly property real widestLabelWidth: Math.max(advanceWidth(qsTr("Loops:")), advanceWidth(qsTr("Session Time:")))
    }

    Rectangle {
        id:         backgroundRect
        width:      control.width + extraWidth
        height:     control.height
        color:      qgcPal.window
        radius:     ScreenTools.defaultFontPixelWidth / 2
        opacity:    0.75
    }

    ColumnLayout {
        id:                 mainLayout
        anchors.margins:    _toolsMargin
        anchors.bottom:     parent.bottom
        anchors.left:       parent.left

        GridLayout {
            columns: 4
            // 安卓上默认间距显得松散：收紧列间距；标签仍右对齐，冒号保持上下对齐
            columnSpacing: ScreenTools.defaultFontPixelWidth * 0.5
            rowSpacing: ScreenTools.defaultFontPixelHeight * 0.2

            QGCLabel { text: qsTr("Speed:");         Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._speedText;      Layout.preferredWidth: control._valueWidth }
            QGCLabel { text: qsTr("Session Time:");  Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._sessionTimeText; Layout.preferredWidth: control._valueWidth }

            QGCLabel { text: qsTr("Longitude:");     Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._longitudeText;  Layout.preferredWidth: control._valueWidth }
            QGCLabel { text: qsTr("Latitude:");      Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._latitudeText;   Layout.preferredWidth: control._valueWidth }

            QGCLabel { text: qsTr("Loops:");         Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._loopCountText;  Layout.preferredWidth: control._valueWidth }
            QGCLabel { text: qsTr("Voltage:");       Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._voltageText;    Layout.preferredWidth: control._valueWidth }

            QGCLabel { text: qsTr("Time:");          Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._timeText;       Layout.preferredWidth: control._valueWidth }
            QGCLabel { text: qsTr("Date:");          Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._dateText;       Layout.preferredWidth: control._valueWidth }
        }

        // 状态区：任务跑满总圈数并停止后提示“任务已完成”
        QGCLabel {
            text:    qsTr("任务已完成")
            color:   qgcPal.colorGreen
            visible: control._taskCompleted
        }
    }

}
