import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// 顶部工具栏的水质参数仪指示器：左侧图标 + 右侧双行数值（主：电导率，次：pH）。
/// 点击弹出完整的水质参数表（WaterQualityIndicatorPage）。
///
/// 数据来自飞控的 NAMED_VALUE_FLOAT（msguid 251），由 Vehicle.waterQuality 提供。
Item {
    id:             control
    objectName:     "toolbar_waterQualityIndicator"
    width:          waterQualityRow.width
    anchors.top:    parent.top
    anchors.bottom: parent.bottom

    /// 始终显示：没收到数据时数值显示 "--"，
    /// 这样即使探头还没上报也能在工具栏上确认图标位置
    property bool showIndicator: true

    property var _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property var _waterQuality:  _activeVehicle ? _activeVehicle.waterQuality : null

    QGCPalette { id: qgcPal }

    /// 没收到过该参数（Fact 值仍是 NaN）时显示 "--"。
    /// 不能把它当成 0：浊度 0 NTU、铵离子 0 mg/L 都是合法读数。
    function displayText(fact) {
        if (!fact) {
            return "--"
        }
        const value = fact.value
        if ((value === undefined) || (value === null) || isNaN(value)) {
            return "--"
        }
        return fact.valueString
    }

    Row {
        id:             waterQualityRow
        anchors.top:    parent.top
        anchors.bottom: parent.bottom
        spacing:        ScreenTools.defaultFontPixelWidth / 2

        QGCColoredImage {
            width:              height
            anchors.top:        parent.top
            anchors.bottom:     parent.bottom
            source:             "/qmlimages/WaterQualityIcon.svg"
            fillMode:           Image.PreserveAspectFit
            sourceSize.height:  height
            color:              qgcPal.text
        }

        // 双行数值：左对齐、垂直居中（与卫星图标旁的数值同级样式）
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing:                0

            QGCLabel {
                color:  qgcPal.text
                text:   control.displayText(control._waterQuality ? control._waterQuality.conductivity : null)
            }

            QGCLabel {
                color:  qgcPal.text
                text:   control.displayText(control._waterQuality ? control._waterQuality.ph : null)
            }
        }
    }

    MouseArea {
        anchors.fill:   parent
        onClicked:      mainWindow.showIndicatorDrawer(waterQualityPage, control)
    }

    Component {
        id: waterQualityPage

        WaterQualityIndicatorPage { }
    }
}
