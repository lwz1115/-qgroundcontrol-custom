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

    readonly property real _labelWidth: labelFontMetrics.widestLabelWidth
    readonly property real _valueWidth: ScreenTools.defaultFontPixelWidth * 10

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
            columnSpacing: ScreenTools.defaultFontPixelWidth
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
            QGCLabel { text: QGroundControl.settingsManager.appSettings.missionLoopCount.rawValue; Layout.preferredWidth: control._valueWidth }
            QGCLabel { text: qsTr("Voltage:");       Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._voltageText;    Layout.preferredWidth: control._valueWidth }

            QGCLabel { text: qsTr("Time:");          Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._timeText;       Layout.preferredWidth: control._valueWidth }
            QGCLabel { text: qsTr("Date:");          Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._dateText;       Layout.preferredWidth: control._valueWidth }
        }
    }

}
