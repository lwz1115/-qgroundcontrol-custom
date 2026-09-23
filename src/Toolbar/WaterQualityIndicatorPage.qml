import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// 水质参数仪弹层：左右两列的键值表（左列项目名，右列数值）。
/// 由 WaterQualityIndicator 通过 mainWindow.showIndicatorDrawer() 弹出。
ToolIndicatorPage {
    id:         control
    showExpand: false

    property var _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property var _waterQuality:  _activeVehicle ? _activeVehicle.waterQuality : null

    /// 没收到过该参数时显示「无数据」（NaN 不代表 0；仅显示文案，取值逻辑不变）
    /// 标签已带单位，数值不再重复拼单位
    function _valueText(fact) {
        if (!fact) {
            return qsTr("No data")
        }
        const value = fact.value
        if ((value === undefined) || (value === null) || isNaN(value)) {
            return qsTr("No data")
        }
        return fact.valueString
    }

    /// 表内容。逐项读取 Fact 的 value，缺项自动变成「无数据」；
    /// 标签里的缩写已换成对应单位（单位写在 qsTr() 外面，不参与翻译）。
    /// 源串一律用英文，中文由 translations/qgc_source_zh_CN.ts 提供。
    readonly property var rows: {
        const wq = control._waterQuality
        return [
            { label: qsTr("Sensor type"),          value: "EXO" },
            { label: qsTr("Conductivity")   + " (mS/cm)",     value: control._valueText(wq ? wq.conductivity    : null) },
            { label: qsTr("pH"),                              value: control._valueText(wq ? wq.ph              : null) },
            { label: qsTr("Dissolved Oxygen") + " (mg/L)",    value: control._valueText(wq ? wq.dissolvedOxygen : null) },
            { label: qsTr("Ammonium")       + " (mg/L)",      value: control._valueText(wq ? wq.ammonium        : null) },
            { label: qsTr("Chlorophyll")    + " (μg/L)",      value: control._valueText(wq ? wq.chlorophyll     : null) },
            { label: qsTr("Phycocyanin")    + " (cells/mL)",  value: control._valueText(wq ? wq.phycocyanin     : null) },
            { label: qsTr("Turbidity")      + " (NTU)",       value: control._valueText(wq ? wq.turbidity       : null) },
        ]
    }

    /// 面板的统一字号（比默认略小，适配多行紧凑排版）
    readonly property real _fontPointSize: ScreenTools.defaultFontPointSize * 0.9

    /// 左列宽度取最长项目名，保证两列都对齐成表格；字号/加粗必须与下方标签一致
    FontMetrics {
        id:             labelMetrics
        font.pointSize: control._fontPointSize
        font.family:    ScreenTools.normalFontFamily
        font.bold:      true

        readonly property real maxLabelWidth: {
            let width = 0
            for (let i = 0; i < control.rows.length; i++) {
                width = Math.max(width, advanceWidth(control.rows[i].label))
            }
            return width
        }
    }

    contentComponent: Component {
        // 传感器数值面板风格：深近黑底、圆角、细边框，无外层分组框
        Rectangle {
            color:                  Qt.rgba(0, 0, 0, 0.85)
            border.color:           Qt.rgba(1, 1, 1, 0.25)
            border.width:           0.1
            radius:                 ScreenTools.defaultBorderRadius
            implicitWidth:          valueGrid.implicitWidth  + ScreenTools.defaultFontPixelWidth * 3
            implicitHeight:         valueGrid.implicitHeight + ScreenTools.defaultFontPixelHeight * 1.5

            ColumnLayout {
                id:                 valueGrid
                anchors.centerIn:   parent
                spacing:            ScreenTools.defaultFontPixelHeight * 0.35

                Repeater {
                    model: control.rows

                    // 每行用 ColumnLayout 包裹，第一行下方加分隔线
                    ColumnLayout {
                        id:                 rowLayout
                        required property var modelData
                        spacing:            ScreenTools.defaultFontPixelHeight * 0.2

                        RowLayout {
                            spacing:            ScreenTools.defaultFontPixelWidth * 2

                            QGCLabel {
                                text:                   rowLayout.modelData.label
                                color:                  "white"
                                font.bold:              true
                                font.pointSize:         control._fontPointSize
                                Layout.preferredWidth:  labelMetrics.maxLabelWidth
                            }

                            QGCLabel {
                                // 等宽字体 + 右对齐，多行数值的小数点上下对齐
                                text:                   rowLayout.modelData.value
                                color:                  "white"
                                font.bold:              true
                                font.pointSize:         control._fontPointSize
                                font.family:            ScreenTools.fixedFontFamily
                                Layout.fillWidth:       true
                                horizontalAlignment:    Text.AlignRight
                            }
                        }

                        // 第一行（传感器类型）下方加分隔线，与数据行区分
                        Rectangle {
                            Layout.fillWidth:   true
                            height:             1
                            color:              Qt.rgba(1, 1, 1, 0.2)
                            visible:            index === 0
                        }
                    }
                }
            }
        }
    }
}
