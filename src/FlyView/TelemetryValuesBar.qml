import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Logging

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

    /// 该 visualItem 是否是 DO_JUMP 动作项（MissionSettingsItem 等没有 command 属性，必须先去判断类型，
    /// 否则 undefined 对比会把设置项误当成 DO_JUMP）
    function _isDoJumpItem(item) {
        return item && (typeof item.command === "number") && (item.command === MAVLinkEnums.MAV_CMD_DO_JUMP)
    }

    // 终点锚点 = 任务末尾的 DO_JUMP 项：ArduPilot 每一圈都必经它
    // （中间圈到达它 → 跳回起点；末圈到达它 → 跳次耗尽、任务结束）。
    // 兼容不循环的单次任务：没有 DO_JUMP 时退回“最后一个坐标航点”。
    readonly property int _loopEndIndex: {
        const items = control._flyMissionController ? control._flyMissionController.visualItems : null
        if (!items || items.count < 2) {
            return -1
        }
        let doJumpIndex = -1
        let lastWaypointIndex = -1
        for (let i = 0; i < items.count; i++) {
            const item = items.get(i)
            if (!item) {
                continue
            }
            if (control._isDoJumpItem(item)) {
                doJumpIndex = item.sequenceNumber
            } else if (item.specifiesCoordinate) {
                lastWaypointIndex = item.sequenceNumber
            }
        }
        return (doJumpIndex >= 0) ? doJumpIndex : lastWaypointIndex
    }

    // 锚点是否来自任务末尾的 DO_JUMP：只有它才能“到达即判定任务结束”；
    // 单次任务回退到坐标航点时，MISSION_CURRENT 是“开始前往”就上报，必须等序号稳定后再确认
    readonly property bool _loopEndIsDoJump: {
        const items = control._flyMissionController ? control._flyMissionController.visualItems : null
        if (!items || items.count < 2) {
            return false
        }
        for (let i = 0; i < items.count; i++) {
            if (control._isDoJumpItem(items.get(i))) {
                return true
            }
        }
        return false
    }

    // 最后一个坐标航点的序号：末圈跑到它以后船就停在那里（DO_JUMP 跳次已耗尽），
    // 用它配合完成确认定时器判定“任务真的跑完了”
    readonly property int _loopLastWaypointIndex: {
        const items = control._flyMissionController ? control._flyMissionController.visualItems : null
        if (!items || items.count < 2) {
            return -1
        }
        let lastWaypointIndex = -1
        for (let i = 0; i < items.count; i++) {
            const item = items.get(i)
            if (item && !control._isDoJumpItem(item) && item.specifiesCoordinate) {
                lastWaypointIndex = item.sequenceNumber
            }
        }
        return lastWaypointIndex
    }

    property int    _completedLoops:   0      ///< 已完成的圈数：每到达一次末尾 DO_JUMP（或它跳回起点）即 +1
    property int    _lastMissionIndex: -1     ///< 上一次的 MISSION_CURRENT 序号
    property bool   _loopRunActive:    false  ///< 本趟是否已起步：起步后才允许计圈
    property bool   _taskCompleted:    false  ///< 本趟任务已跑满总圈数并结束
    property bool   _showCompletedNotice: false ///< 是否短暂显示“任务已完成”通知（非模态）
    property string _loopMissionKey:   ""     ///< 本趟任务的特征（起点/终点/总圈数），用来识别“任务是否被替换”

    /// 总圈数（船上已生效值），可能为 null（拿不到时仍计圈，但不判定完成）
    readonly property var _totalLoops: control._missionLoopCount

    /// 完成确认超时：跑满总圈数、或末圈停在终点后序号长时间不变，就确认任务已结束
    readonly property int _taskCompleteConfirmTimeoutMs: 8000

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

    /// 把“任务运行中/已完成”写回飞行界面的任务控制器，供规划界面拦截“任务执行中下发新任务”。
    /// 只在主遥测栏写（多机卡片不写），避免多机时相互覆盖。
    function _publishTaskState() {
        if (specificVehicleForCard) {
            return
        }
        const planController = globals.planMasterControllerFlyView
        if (planController) {
            // 任务已判完成后不再算“运行中”，否则停在总圈数上仍处于任务模式时会一直拦着不让上传新任务
            planController.missionTaskRunning = control._missionRunning && !control._taskCompleted
            planController.missionTaskCompleted = control._taskCompleted
        }
    }

    // 回到“本趟还没起步”的状态，计数清零
    function _resetLoopProgress() {
        _completedLoops = 0
        _lastMissionIndex = -1
        _loopRunActive = false
        _taskCompleted = false
        _loopMissionKey = control._loopMissionKeyOf()
        completeConfirmTimer.stop()
        control._publishTaskState()
    }

    // 计圈规则：锚点是任务末尾的 DO_JUMP（MISSION_CURRENT 是“开始前往该航点”时上报）。
    //   a) 起步：本趟未起步且序号已进入任务范围 → 清零重计
    //   b) 新一趟：本趟已完成、又回到起点 → 清零重计
    //   c) 到达锚点：序号等于末尾 DO_JUMP 且上一次不是它 → 完成一圈（末圈跑到它说明跳次已耗尽）
    //   d) 从航尾直接回到起点：等价于“DO_JUMP 已经执行过”（带 DO_JUMP 的任务只有它能跳回起点），
    //      按同一件事计一圈（有些固件不单独上报 DO_JUMP 序号）
    //   e) 末圈停在终点：差最后一圈且序号稳定停在终点区域 → 启动完成确认，确认后补上末圈
    //   f) 圈数已满但未确认（单次任务没有 DO_JUMP 时）→ 序号稳定后确认完成
    //   g) 其余只记录上一次序号（跳点不改圈次）
    function _updateLoopProgress(missionIndex) {
        // 只要起点有效即可计圈：终点锚点异常时不应把整个计圈停掉（兜底分支仍可用）
        if (_loopStartIndex < 0) {
            return
        }

        // 诊断开关：沿用 PlanMasterController 日志分类（设置页里的全名就是它）
        if (QGCLoggingCategoryManager.isCategoryEnabled("PlanManager.PlanMasterController")) {
            console.log("TelemetryValuesBar loopProgress index", missionIndex,
                        "start", _loopStartIndex, "end", _loopEndIndex, "lastWp", _loopLastWaypointIndex,
                        "total", _totalLoops, "done", _completedLoops, "active", _loopRunActive, "completed", _taskCompleted)
        }

        // 序号一变说明船还在动，取消上一次的完成确认
        completeConfirmTimer.stop()

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
        } else if ((missionIndex === _loopEndIndex) && (_lastMissionIndex !== _loopEndIndex)) {
            // 到达末尾 DO_JUMP：这一圈完成
            control._completeOneLoop()
        } else if ((missionIndex === _loopStartIndex) && (_lastMissionIndex > _loopStartIndex) && (_lastMissionIndex !== _loopEndIndex)) {
            // 从航尾直接回到起点：与“DO_JUMP 已执行”是同一件事，计一圈
            control._completeOneLoop()
        } else if ((missionIndex === _loopLastWaypointIndex) && (_lastMissionIndex !== _loopLastWaypointIndex)) {
            // 末圈跑到最后一个航点后停住：等完成确认
            control._armFinalConfirm()
        } else if (!_taskCompleted && (_totalLoops !== null) && (_completedLoops >= _totalLoops)) {
            // 圈数已满但还没确认完成（单次任务到达终点却仍在上报序号）：序号稳定后即确认
            completeConfirmTimer.restart()
        }

        _lastMissionIndex = missionIndex
    }

    /// 完成一圈：计数 +1；跑满总圈数时：
    ///   · 有 DO_JUMP → 到达它说明跳次已耗尽，立即判定完成（并由完成确认发通知）
    ///   · 单次任务（无 DO_JUMP，锚点是坐标航点）→ 序号只是“开始前往终点”就上报，
    ///     不能立即判定完成，交给完成确认定时器等序号稳定后再判定
    function _completeOneLoop() {
        _completedLoops++
        if ((_totalLoops === null) || (_completedLoops < _totalLoops)) {
            return
        }
        if (_loopEndIsDoJump) {
            _taskCompleted = true
        }
        completeConfirmTimer.restart()
        control._publishTaskState()
    }

    /// 末圈（差最后一圈）停在终点区域时启动完成确认：序号长时间不再变化就认为任务已结束
    function _armFinalConfirm() {
        if (_taskCompleted || (_totalLoops === null)) {
            return
        }
        if (_completedLoops !== (_totalLoops - 1)) {
            return
        }
        completeConfirmTimer.restart()
    }

    // 完成确认超时：① 只在“还差圈数”时补上末圈（已计满不再 +1，避免末圈双计）；
    // ② 判定任务已完成并发一次非模态完成通知。
    // 只是一次性的完成确认，不是周期轮询任务，也不触发任何上传。
    // 注：停船/保位/切动力/上报 COMPLETED 由飞控负责（DO_JUMP 跳次耗尽后不再跳回）；
    // 若某些固件需要 QGC 主动下发 HOLD/暂停命令，可在这个函数里补（飞控端需配合上报 COMPLETED）。
    function _handleTaskConfirmed() {
        if ((_totalLoops !== null) && (_completedLoops < _totalLoops)) {
            _completedLoops++
        }
        _taskCompleted = true
        control._publishTaskState()
        _showCompletedNotice = true
        completedNoticeTimer.restart()
    }

    Timer {
        id: completeConfirmTimer
        interval: control._taskCompleteConfirmTimeoutMs
        onTriggered: control._handleTaskConfirmed()
    }

    // 完成通知（非模态）：在状态区短暂显示一条提示，不抢焦点、不挡操作
    Timer {
        id: completedNoticeTimer
        interval: 6000
        onTriggered: control._showCompletedNotice = false
    }

    // 解锁/飞行模式变化时同步“任务运行中”状态（用于拦截任务执行中下发新任务）
    on_MissionRunningChanged: control._publishTaskState()

    // visualItems 重建时是否清零见 _checkMissionReplaced()：
    // 同一个任务（重连、重新下载、任务执行中重载）保持已跑圈数；
    // 只有“上传”才会清零（见下面的 missionUploadComplete 信号）。
    // 也刻意不在载具上锁时清零，否则“停到终点”后看不到 3/3。
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

    // 只有“上传”才清零计圈（上传即视为新任务）：重连、重新下载都保持已跑圈数。
    // 单纯看 visualItems 重建区分不出上传与下载，所以要靠这个只在上传完成时发出的信号。
    Connections {
        target: globals.planMasterControllerFlyView

        function onMissionUploadComplete() {
            control._resetLoopProgress()
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

        // 完成通知（非模态，短暂显示后自动消失）
        QGCLabel {
            text:        qsTr("循环任务已跑完，船已停在最后一个航点")
            color:       qgcPal.colorGreen
            visible:     control._showCompletedNotice
            Layout.fillWidth: true
            wrapMode:    Text.WordWrap
        }
    }

}
