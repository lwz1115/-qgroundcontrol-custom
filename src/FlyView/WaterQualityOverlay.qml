import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// 飞行界面左下角的水质实时折线图入口
///
/// · 一枚黑白水滴图标，点击弹出简易折线图；
/// · 默认显示全部水质参数的曲线（一参数一颜色），下拉框可只看单个参数；
/// · 只做“实时观测”：每 5 秒采一个点，只在内存里滚动保留最近 20 分钟，
///   不写任何文件、不做任何保存（数据保存走任务流程）；
/// · “剔除极值”勾选框：极大值 / 极小值不参与显示。
///
/// 由 FlyViewCustomLayer 实例化，放在 QGC 自定义叠加层里。
Item {
    id: control

    /// 上层传下来的可用区域（已扣掉工具栏、虚拟摇杆、画中画视频等占位）
    property var parentToolInsets
    /// 摄像头小窗（FlyView.qml 的 PipView，缩到最小即“图标”）。卡片紧贴它顶部上方，随它缩放/移动。
    property var pipView

    readonly property var _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    readonly property var _waterQuality:  _activeVehicle ? _activeVehicle.waterQuality : null
    readonly property bool _singleMode:   _selectedParameter.length > 0

    /// 图标连同外边距占用的空间，回报给上层 inset，避免盖住地图上的其它控件
    readonly property real reservedWidth:  _iconSize + _margin * 2
    readonly property real reservedHeight: _iconSize + _margin * 2
    /// 从左下角算起、到水滴图标顶部的高度（供上层在其上方再叠加采样按钮）
    readonly property real reservedAboveIconHeight: _margin + _bottomInset + _iconSize + _margin

    readonly property real _leftInset:   (parentToolInsets && parentToolInsets.leftEdgeBottomInset) ? parentToolInsets.leftEdgeBottomInset : 0
    readonly property real _bottomInset: (parentToolInsets && parentToolInsets.bottomEdgeLeftInset) ? parentToolInsets.bottomEdgeLeftInset : 0

    /// 摄像头是否在显示（主画面有源）。有源时卡片列紧贴小窗顶部，无源时落到屏幕左下角。
    readonly property bool _camActive: QGroundControl.videoManager.isStreamSource
                                        || QGroundControl.videoManager.isUvc
    /// 卡片边长：随摄像头小窗宽度联动（两卡片严格一致），封顶防单边过大
    readonly property real _cardSize:  (_camActive && pipView)
                                       ? Math.min(pipView.width * 0.28, ScreenTools.defaultFontPixelHeight * 1.9)
                                       : ScreenTools.defaultFontPixelHeight * 1.7
    /// 卡片间距 / 两卡竖排总高 / 卡片左缘（贴齐小窗左缘）/ 卡片列顶部（紧贴小窗顶）
    readonly property real _spacing:    ScreenTools.defaultFontPixelWidth * 0.25
    readonly property real _rowHeight:  control._cardSize * 2 + control._spacing
    readonly property real _iconX:      pipView ? pipView.x : control._margin
    readonly property real _iconsTopY:  control._camActive
                                        ? (pipView.y - control._rowHeight - control._spacing)
                                        : (parent.height - control._rowHeight - control._margin - control._bottomInset)

    readonly property real _margin:   ScreenTools.defaultFontPixelWidth * 0.75
    readonly property real _iconSize: ScreenTools.defaultFontPixelHeight * 1.7

    /// 5 秒一个采样点；240 个点约 20 分钟，只在内存里滚动，不落盘
    readonly property int _sampleIntervalMs: 5000
    readonly property int _maxSamples:       240

    /// 七个水质参数：key 必须与 VehicleWaterQualityFactGroup 的属性名一致
    readonly property var _parameterDefs: [
        { key: "conductivity",    label: qsTr("Conductivity"),    color: "#42A5F5" },
        { key: "ph",              label: qsTr("pH"),              color: "#66BB6A" },
        { key: "dissolvedOxygen", label: qsTr("Dissolved Oxygen"), color: "#26C6DA" },
        { key: "ammonium",        label: qsTr("Ammonium"),        color: "#FFEE58" },
        { key: "chlorophyll",     label: qsTr("Chlorophyll"),     color: "#AB47BC" },
        { key: "phycocyanin",     label: qsTr("Phycocyanin"),     color: "#FF7043" },
        { key: "turbidity",       label: qsTr("Turbidity"),       color: "#8D6E63" }
    ]

    /// 下拉框选项：第一项是“全部参数”，其余按 _parameterDefs 顺序
    readonly property var _parameterLabels: {
        const labels = [qsTr("All parameters")]
        for (const def of _parameterDefs) {
            labels.push(def.label)
        }
        return labels
    }

    /// 只看单个参数时，标题旁显示该参数的单位
    readonly property string _selectedUnits: {
        if (!_singleMode || !_waterQuality) {
            return ""
        }
        const fact = _waterQuality[_selectedParameter]
        return fact ? fact.units : ""
    }

    property string _selectedParameter: ""
    property bool   _filterExtremes:    true
    property var    _samples:           []
    property int    _revision:          0

    /// 采一帧：七个参数各自取值，整帧一个有效值都没有就跳过（例如还没收到遥测）
    function recordSample() {
        const waterQuality = _waterQuality
        if (!waterQuality) {
            return
        }

        const values = {}
        let hasValue = false
        for (const def of _parameterDefs) {
            const fact = waterQuality[def.key]
            const value = fact ? fact.value : NaN
            if (isFinite(value)) {
                values[def.key] = value
                hasValue = true
            }
        }
        if (!hasValue) {
            return
        }

        const samples = _samples.slice()
        samples.push({ t: Date.now(), values: values })
        while (samples.length > _maxSamples) {
            samples.shift()
        }
        _samples = samples
        _revision++
    }

    function clearSamples() {
        _samples = []
        _revision++
    }

    Timer {
        interval:         control._sampleIntervalMs
        repeat:           true
        running:          control._waterQuality !== null
        triggeredOnStart: true
        onTriggered:      control.recordSample()
    }

    Rectangle {
        id: iconButton

        // 方形卡片（与摄像头小窗同风格）：与采样卡片一竖排，水质在下方、紧贴摄像头小窗顶部
        x:              control._iconX
        y:              control._iconsTopY + control._cardSize + control._spacing
        width:           control._cardSize
        height:          control._cardSize
        radius:          ScreenTools.defaultBorderRadius
        color:           Qt.rgba(0, 0, 0, 0.6)
        border.color:    Qt.rgba(1, 1, 1, iconMouseArea.containsMouse ? 0.75 : 0.35)
        border.width:    1

        QGCColoredImage {
            anchors.centerIn: parent
            width:            parent.width * 0.58
            height:           parent.height * 0.58
            source:           "/qmlimages/WaterQualityDropIcon.svg"
            color:            "white"
        }

        MouseArea {
            id:           iconMouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked:    chartPopup.visible ? chartPopup.close() : chartPopup.open()
        }
    }

    Popup {
        id:             chartPopup
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

            RowLayout {
                Layout.fillWidth: true
                spacing:          control._margin

                QGCLabel {
                    Layout.fillWidth: true
                    text:             qsTr("Water Quality Trend")
                    color:            "white"
                    font.bold:        true
                }

                QGCComboBox {
                    id:                    parameterCombo
                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 13
                    model:                 control._parameterLabels
                    // 用户改选后由 onActivated 改状态，这里只在初始 / 重置时同步
                    currentIndex:          control._selectedIndex
                    onActivated: (index) => control._selectedParameter = (index === 0) ? "" : control._parameterDefs[index - 1].key
                }

                QGCLabel {
                    text:    control._selectedUnits
                    color:   Qt.rgba(1, 1, 1, 0.7)
                    visible: text.length > 0
                }
            }

            WaterQualityLiveChart {
                id:                     liveChart
                Layout.fillWidth:       true
                Layout.preferredHeight: Math.round(control._popupWidth * 0.45)
                parameterDefs:          control._parameterDefs
                samples:                control._samples
                revision:               control._revision
                selectedParameter:      control._selectedParameter
                filterExtremes:         control._filterExtremes
            }

            QGCLabel {
                Layout.fillWidth: true
                visible:          !control._singleMode
                text:             qsTr("Each parameter is scaled to its own range")
                color:            Qt.rgba(1, 1, 1, 0.7)
                font.pointSize:   ScreenTools.defaultFontPointSize * 0.85
                wrapMode:         Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing:          control._margin

                QGCCheckBox {
                    text:      qsTr("Remove min/max")
                    textColor: "white"
                    checked:   control._filterExtremes
                    onToggled: control._filterExtremes = checked
                }

                QGCLabel {
                    Layout.fillWidth:   true
                    Layout.leftMargin:  Math.round(control._margin * 0.5)
                    text:               qsTr("Live view only, nothing is saved")
                    color:              Qt.rgba(1, 1, 1, 0.7)
                    font.pointSize:     ScreenTools.defaultFontPointSize * 0.8
                    elide:              Text.ElideRight
                }

                QGCButton {
                    text:      qsTr("Clear")
                    onClicked: control.clearSamples()
                }
            }

            GridLayout {
                Layout.fillWidth: true
                visible:          !control._singleMode
                columns:          2
                columnSpacing:    control._margin
                rowSpacing:       Math.round(control._margin * 0.5)

                Repeater {
                    model: control._parameterDefs

                    RowLayout {
                        required property var modelData
                        spacing: Math.round(control._margin * 0.5)

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width:            9
                            height:           9
                            radius:           2
                            color:            modelData.color
                        }

                        QGCLabel {
                            text:           modelData.label
                            color:          "white"
                            font.pointSize: ScreenTools.defaultFontPointSize * 0.85
                        }
                    }
                }
            }
        }
    }

    /// 弹层宽度：随字体缩放，但不超出可用区域
    readonly property real _popupWidth: Math.min(Math.max(ScreenTools.defaultFontPixelWidth * 40, 300),
                                                 Math.max(240, width - _margin * 4))

    /// 下拉框当前下标（0 = 全部参数）
    readonly property int _selectedIndex: {
        if (!_singleMode) {
            return 0
        }
        for (let i = 0; i < _parameterDefs.length; i++) {
            if (_parameterDefs[i].key === _selectedParameter) {
                return i + 1
            }
        }
        return 0
    }

    onVisibleChanged: {
        if (!visible && chartPopup.visible) {
            chartPopup.close()
        }
    }
}
