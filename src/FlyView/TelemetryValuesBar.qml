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

    // 循环次数跟随"任务设置"：与规划界面的编辑入口共用同一个 Fact，改完立即一致。
    // 飞行界面从载具下载任务时，同一 Fact 也会由 DO_JUMP 反推出载具真实值。
    readonly property var _missionLoopCount: {
        const planController = globals.planMasterControllerPlanView
        const missionController = planController ? planController.missionController : null
        if (!missionController || missionController.visualItems.count === 0) {
            return null
        }
        const settingsItem = missionController.visualItems.get(0)
        return (settingsItem && settingsItem.loopCount) ? settingsItem.loopCount.rawValue : null
    }

    // 计数用的控制器：飞行视图那份，实时跟踪载具 MISSION_CURRENT（规划视图那份只跟编辑内容，不能用来算圈）
    readonly property var _flyMissionController: {
        const planController = globals.planMasterControllerFlyView
        return planController ? planController.missionController : null
    }

    // 回跳起点序号（DO_JUMP 的回跳目标，即第一个航点的序号）：航点不足 2 项时无法判圈，返回 -1
    readonly property int _loopStartIndex: {
        const items = control._flyMissionController ? control._flyMissionController.visualItems : null
        if (!items || items.count < 2) {
            return -1
        }
        const firstWaypoint = items.get(1)
        return firstWaypoint ? firstWaypoint.sequenceNumber : -1
    }

    property int  _completedLoops:   0      ///< 已完成的整圈数：每次从航尾跳回起点算一圈
    property int  _lastMissionIndex: -1     ///< 上一次的 MISSION_CURRENT 序号，用来识别“跳回起点”
    property bool _loopRunActive:    false  ///< 本趟是否已起步：起步后才允许计圈

    // 显示“已循环次数/总次数”，例如 3/5；拿不到总次数时显示 “--”
    readonly property string _loopCountText: _missionLoopCount === null ? "--" : (_completedLoops + "/" + _missionLoopCount)

    // 回到“本趟还没起步”的状态，计数清零
    function _resetLoopProgress() {
        _completedLoops = 0
        _lastMissionIndex = -1
        _loopRunActive = false
    }

    // 判圈：只有“序号在起点之后、又跳回起点”才算跑完一圈；
    // 起点首次出现只是本趟起步，直接复位成 0 起。载具不上报序号时保持 0，不报错。
    function _updateLoopProgress(missionIndex) {
        if (_loopStartIndex < 0) {
            return
        }
        if ((missionIndex === _loopStartIndex) && _loopRunActive && (_lastMissionIndex > _loopStartIndex)) {
            _completedLoops++
        } else if (!_loopRunActive && (missionIndex >= _loopStartIndex)) {
            _resetLoopProgress()
            _loopRunActive = true
        }
        _lastMissionIndex = missionIndex
    }

    // 本趟结束（载具上锁）→ 新一趟从 0 开始
    Connections {
        target: control._vehicle

        function onArmedChanged() {
            if (!(control._vehicle && control._vehicle.armed)) {
                control._resetLoopProgress()
            }
        }
    }

    // 任务重新上传/下载、任务被替换 → 也当作新一趟，计数清零
    Connections {
        target: control._flyMissionController

        function onCurrentMissionIndexChanged(missionIndex) {
            control._updateLoopProgress(missionIndex)
        }
        function onSyncInProgressChanged() {
            const missionController = control._flyMissionController
            if (missionController && !missionController.syncInProgress) {
                control._resetLoopProgress()
            }
        }
        function onVisualItemsReset() {
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
