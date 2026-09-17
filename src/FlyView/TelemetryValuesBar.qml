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

    property int    _completedLoops:   0      ///< 已完成的圈数：到达最后一个航点即 +1
    property int    _lastMissionIndex: -1     ///< 上一次的 MISSION_CURRENT 序号，用来识别“刚到达终点”
    property bool   _loopRunActive:    false  ///< 本趟是否已起步：起步后才允许计圈
    property string _loopMissionKey:   ""     ///< 本趟任务的特征（起点/终点/总圈数），用来识别“任务是否被替换”

    // 显示“已循环次数/总次数”，例如 3/5；拿不到总次数时显示 “--”
    readonly property string _loopCountText: _missionLoopCount === null ? "--" : (_completedLoops + "/" + _missionLoopCount)

    /// 任务特征：起点/终点/总圈数一致就认为是同一个任务
    function _loopMissionKeyOf() {
        return control._loopStartIndex + ":" + control._loopEndIndex + ":" + control._missionLoopCount
    }

    // 回到“本趟还没起步”的状态，计数清零
    function _resetLoopProgress() {
        _completedLoops = 0
        _lastMissionIndex = -1
        _loopRunActive = false
        _loopMissionKey = control._loopMissionKeyOf()
    }

    // 计圈规则：只看“是否到达最后一个航点”，跳点不改圈次、跳点到终点同样算到达。
    //   a) 起步：本趟未起步且序号已进入任务范围 → 清零重计
    //   b) 新一趟：已起步、又回到起点、且上一趟已计满总圈数 → 清零重计（跑完后再跑同一任务）
    //   c) 到终点：已起步、到达终点、且上一次不是终点 → 完成一圈 +1（末圈也 +1）
    //   d) 其余只记录上一次序号
    function _updateLoopProgress(missionIndex) {
        if ((_loopStartIndex < 0) || (_loopEndIndex < _loopStartIndex)) {
            return
        }

        const totalLoops = (_missionLoopCount === null) ? -1 : _missionLoopCount
        if (!_loopRunActive) {
            if (missionIndex >= _loopStartIndex) {
                _resetLoopProgress()
                _loopRunActive = true
            }
        } else if ((missionIndex === _loopStartIndex) && (totalLoops > 0) && (_completedLoops >= totalLoops)) {
            // 上一趟已经跑满，又回到起点 → 新的一趟，从 0 重新计
            _resetLoopProgress()
            _loopRunActive = true
        } else if ((missionIndex === _loopEndIndex) && (_lastMissionIndex !== _loopEndIndex)) {
            _completedLoops++
        }

        _lastMissionIndex = missionIndex
    }

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
    }

}
