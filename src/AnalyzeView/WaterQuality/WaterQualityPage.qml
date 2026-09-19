import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtGraphs

import QGroundControl
import QGroundControl.Controls

/// 水质监测：导入 Excel(.xlsx)/CSV 表格，用折线图或热力图查看各水质参数随时间的变化。
///
/// 表格约定（自适应）：第 1 行表头 = 参数名，第 1 列 = 时间，其余列为数值。
/// 时间轴与板载日志一致，统一用“相对首条记录的秒数”，显示成 HH:MM:SS。
///
/// 说明：QtGraphs 的 GraphsView 只支持一条 Y 轴，所以“双 Y 轴”用上下两张共享时间轴的图实现
/// （左轴参数一张、右轴参数一张），与 Log Viewer 的双图联动做法一致。
AnalyzePage {
    id:                 page
    pageComponent:      pageComponent
    pageDescription:    qsTr("Import water quality monitoring data (Excel .xlsx or .csv) and view each parameter over time as a line chart or a heat map.")
    allowPopout:        true

    // ---------------------------------------------------------------------
    // 数据源
    // ---------------------------------------------------------------------
    WaterQualityLog {
        id: waterLog
    }

    // ---------------------------------------------------------------------
    // 界面状态
    // ---------------------------------------------------------------------
    property bool   _lineMode:      true          ///< true: 折线图；false: 热力图
    property var    _checked:       ({})          ///< 参数名 -> 是否显示
    property var    _rightAxis:     ({})          ///< 参数名 -> 是否走右轴（下面那张图）
    property real   _filterMin:     0             ///< 时间筛选起点（秒）
    property real   _filterMax:     1             ///< 时间筛选终点（秒）
    property real   _zoomMin:       0             ///< 折线图当前 X 轴范围
    property real   _zoomMax:       1
    property real   _hoverX:        -1            ///< 悬停位置（X 轴值，-1 表示不显示）
    property var    _hoverRows:     []            ///< 悬停面板内容 [{name, value, color}]
    property var    _legendRows:    []            ///< 图例 [{name, color, right}]

    readonly property int  _heatmapColumns: 120   ///< 热力图横向格数

    readonly property var _chartColors: [
        "#1E88E5", "#E53935", "#43A047", "#FB8C00", "#8E24AA", "#00ACC1",
        "#FDD835", "#D81B60", "#6D4C41", "#546E7A", "#3949AB", "#00897B",
    ]

    /// 参与绘制（已勾选）的参数名
    readonly property var _checkedNames: {
        var names = []
        if (!waterLog.loaded) {
            return names
        }
        for (var i = 0; i < waterLog.parameterNames.length; i++) {
            var name = waterLog.parameterNames[i]
            if (_checked[name]) {
                names.push(name)
            }
        }
        return names
    }

    /// 走左轴的参数名
    readonly property var _leftNames: {
        var names = []
        for (var i = 0; i < _checkedNames.length; i++) {
            if (!_rightAxis[_checkedNames[i]]) {
                names.push(_checkedNames[i])
            }
        }
        return names
    }

    /// 走右轴的参数名
    readonly property var _rightNames: {
        var names = []
        for (var i = 0; i < _checkedNames.length; i++) {
            if (_rightAxis[_checkedNames[i]]) {
                names.push(_checkedNames[i])
            }
        }
        return names
    }

    // ---------------------------------------------------------------------
    // 工具函数
    // ---------------------------------------------------------------------

    function parameterColor(name) {
        var index = waterLog.parameterNames.indexOf(name)
        if (index < 0) {
            return _chartColors[0]
        }
        return _chartColors[index % _chartColors.length]
    }

    /// 秒 -> "HH:MM:SS"（相对首条记录）
    function timeText(seconds) {
        if (isNaN(seconds)) {
            return "--"
        }
        var total = Math.max(0, Math.floor(seconds))
        var h = Math.floor(total / 3600)
        var m = Math.floor(total / 60) % 60
        var s = total % 60
        function two(v) { return v < 10 ? "0" + v : String(v) }
        return two(h) + ":" + two(m) + ":" + two(s)
    }

    /// "HH:MM:SS" 或纯秒 -> 秒；解析失败返回 NaN
    function textToSeconds(text) {
        var t = String(text).trim()
        if (t === "") {
            return NaN
        }
        if (t.indexOf(":") >= 0) {
            var parts = t.split(":")
            var seconds = 0
            for (var i = 0; i < parts.length; i++) {
                var v = Number(parts[i])
                if (isNaN(v)) {
                    return NaN
                }
                seconds = seconds * 60 + v
            }
            return seconds
        }
        var value = Number(t)
        return isNaN(value) ? NaN : value
    }

    function _resetSelection() {
        var checked = {}
        var right = {}
        for (var i = 0; i < waterLog.parameterNames.length; i++) {
            var name = waterLog.parameterNames[i]
            checked[name] = true
            right[name] = false
        }
        _checked = checked
        _rightAxis = right
    }

    function _applyFilters() {
        if (!waterLog.loaded) {
            return
        }
        _filterMin = waterLog.minTime
        _filterMax = waterLog.maxTime
        _zoomMin = _filterMin
        _zoomMax = _filterMax
        startField.text = timeText(_filterMin)
        endField.text = timeText(_filterMax)
    }

    function importFile(file) {
        if (waterLog.loadFile(file)) {
            _resetSelection()
            _applyFilters()
            legendRepeater.model = _buildLegend()
            refreshChart()
        } else {
            legendRepeater.model = []
        }
    }

    function _buildLegend() {
        var rows = []
        for (var i = 0; i < _checkedNames.length; i++) {
            var name = _checkedNames[i]
            rows.push({ name: name, color: parameterColor(name), right: !!_rightAxis[name] })
        }
        _legendRows = rows
        return rows
    }

    function toggleParameter(name, visible) {
        var checked = _checked
        checked[name] = visible
        _checked = checked
        legendRepeater.model = _buildLegend()
        refreshChart()
    }

    function toggleAxis(name) {
        var right = _rightAxis
        right[name] = !right[name]
        _rightAxis = right
        legendRepeater.model = _buildLegend()
        refreshChart()
    }

    /// 按当前勾选与缩放范围重建曲线（沿用 Log Viewer 的做法：复用 series，只 clear + 重新填点）
    function refreshChart() {
        if (!waterLog.loaded || !_lineMode) {
            return
        }
        _fillChart(leftChart, _leftNames)
        _fillChart(rightChart, _rightNames)
        rightChart.visible = _rightNames.length > 0
    }

    function _fillChart(chart, names) {
        if (!chart) {
            return
        }
        chart.beginUpdate()
        chart.clearSeries(names)
        for (var i = 0; i < names.length; i++) {
            var name = names[i]
            var points = waterLog.samplesForParameter(name, _zoomMin, _zoomMax,
                                                      Math.max(1, Math.floor(chart.plotWidth)))
            var range = waterLog.parameterMinMax(name)
            chart.setSeriesPoints(name, parameterColor(name), points, range.min, range.max)
        }
        chart.endUpdate()
        chart.setAxisRange(_zoomMin, _zoomMax)
    }

    /// 切换折线图 / 热力图时刷新对应的图
    on_LineModeChanged: {
        if (_lineMode) {
            refreshChart()
        } else {
            heatmap.refresh()
        }
    }

    /// 悬停：找出离鼠标最近的时间点，收集各参数在该时刻的数值
    function updateHover(xValue) {
        if (!waterLog.loaded) {
            return
        }
        _hoverX = xValue
        var rows = []
        for (var i = 0; i < _checkedNames.length; i++) {
            var name = _checkedNames[i]
            var points = waterLog.samplesForParameter(name, xValue - 3600, xValue + 3600, 0)
            var best = NaN
            var bestDistance = Number.MAX_VALUE
            for (var j = 0; j < points.length; j++) {
                var distance = Math.abs(points[j].x - xValue)
                if (distance < bestDistance) {
                    bestDistance = distance
                    best = points[j].y
                }
            }
            rows.push({
                name:  name,
                value: isNaN(best) ? "--" : best.toFixed(3),
                color: parameterColor(name)
            })
        }
        _hoverRows = rows
    }

    // ---------------------------------------------------------------------
    // 导入文件对话框
    // ---------------------------------------------------------------------
    QGCFileDialog {
        id:             importDialog
        title:          qsTr("Select water quality data file")
        folder:         QGroundControl.settingsManager.appSettings.missionSavePath
        nameFilters:    [ qsTr("Excel workbook (*.xlsx)"), qsTr("CSV table (*.csv)"), qsTr("All Files (*)") ]
        onAcceptedForLoad: (file) => page.importFile(file)
    }

    // ---------------------------------------------------------------------
    // 页面内容
    // ---------------------------------------------------------------------
    Component {
        id: pageComponent

        ColumnLayout {
            anchors.fill:   parent
            spacing:        ScreenTools.defaultFontPixelHeight * 0.5

            // ---------------- 工具条 ----------------
            RowLayout {
                Layout.fillWidth: true
                spacing:          ScreenTools.defaultFontPixelWidth

                QGCButton {
                    text:    qsTr("📁 Import Excel")
                    onClicked: importDialog.open()
                }

                QGCLabel {
                    text:               waterLog.loaded ? waterLog.fileName : qsTr("No data imported yet")
                    color:              waterLog.errorString !== "" ? qgcPal.colorRed : qgcPal.text
                    elide:              Text.ElideMiddle
                    Layout.fillWidth:   true
                }

                QGCLabel {
                    text:               qsTr("%1 records").arg(waterLog.sampleCount)
                    visible:            waterLog.loaded
                }
            }

            QGCLabel {
                text:       waterLog.errorString
                color:      qgcPal.colorRed
                visible:    waterLog.errorString !== ""
                wrapMode:   Text.WordWrap
                Layout.fillWidth: true
            }

            // ---------------- 图表类型 + 时间筛选 ----------------
            RowLayout {
                Layout.fillWidth: true
                spacing:          ScreenTools.defaultFontPixelWidth
                visible:          waterLog.loaded

                QGCRadioButton {
                    id:      lineRadio
                    text:    qsTr("Line Chart")
                    checked: page._lineMode
                    onClicked: page._lineMode = true
                }
                QGCRadioButton {
                    text:    qsTr("Heat Map")
                    checked: !page._lineMode
                    onClicked: page._lineMode = false
                }

                Rectangle {
                    Layout.preferredWidth:  1
                    Layout.fillHeight:      true
                    color:                  qgcPal.text
                    opacity:                0.3
                }

                QGCLabel { text: qsTr("Time range:") }

                QGCTextField {
                    id:                     startField
                    Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 10
                    onEditingFinished: {
                        var seconds = page.textToSeconds(text)
                        if (!isNaN(seconds) && (seconds < page._zoomMax)) {
                            page._filterMin = seconds
                            page._zoomMin = seconds
                            page.refreshChart()
                        } else {
                            text = page.timeText(page._filterMin)
                        }
                    }
                }

                QGCLabel { text: qsTr("to") }

                QGCTextField {
                    id:                     endField
                    Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 10
                    onEditingFinished: {
                        var seconds = page.textToSeconds(text)
                        if (!isNaN(seconds) && (seconds > page._zoomMin)) {
                            page._filterMax = seconds
                            page._zoomMax = seconds
                            page.refreshChart()
                        } else {
                            text = page.timeText(page._filterMax)
                        }
                    }
                }

                QGCButton {
                    text:       qsTr("Reset Zoom")
                    visible:    page._lineMode
                    onClicked: {
                        page._zoomMin = page._filterMin
                        page._zoomMax = page._filterMax
                        page.refreshChart()
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // ---------------- 参数勾选（折线图模式下可切左右轴） ----------------
            Flow {
                Layout.fillWidth: true
                spacing:          ScreenTools.defaultFontPixelWidth * 0.75
                visible:          waterLog.loaded

                Repeater {
                    model: waterLog.parameterNames

                    RowLayout {
                        spacing: ScreenTools.defaultFontPixelWidth * 0.25

                        QGCCheckBox {
                            text:       modelData
                            checked:    !!page._checked[modelData]
                            onClicked:  page.toggleParameter(modelData, checked)
                        }

                        QGCButton {
                            // 折线图模式下切换该参数走左轴还是右轴
                            visible:    page._lineMode
                            text:       page._rightAxis[modelData] ? qsTr("Right axis") : qsTr("Left axis")
                            onClicked:  page.toggleAxis(modelData)
                        }
                    }
                }
            }

            // ---------------- 图表本体 ----------------
            Item {
                Layout.fillWidth:   true
                Layout.fillHeight:  true

                // 折线图：上下两张共享时间轴的图（左轴组 / 右轴组）
                ColumnLayout {
                    anchors.fill: parent
                    spacing:      0
                    visible:      page._lineMode

                    QualityLineChart {
                        id:                 leftChart
                        Layout.fillWidth:   true
                        Layout.fillHeight:  true
                        onHoverXChanged:    (x) => page.updateHover(x)
                        onZoomRequested:    (minX, maxX) => {
                            page._zoomMin = minX
                            page._zoomMax = maxX
                            startField.text = page.timeText(minX)
                            endField.text = page.timeText(maxX)
                            page.refreshChart()
                        }
                    }

                    QualityLineChart {
                        id:                 rightChart
                        Layout.fillWidth:   true
                        Layout.fillHeight:  true
                        visible:            false
                        onHoverXChanged:    (x) => page.updateHover(x)
                        onZoomRequested:    (minX, maxX) => {
                            page._zoomMin = minX
                            page._zoomMax = maxX
                            startField.text = page.timeText(minX)
                            endField.text = page.timeText(maxX)
                            page.refreshChart()
                        }
                    }
                }

                // 热力图
                QualityHeatmap {
                    id:             heatmap
                    anchors.fill:   parent
                    visible:        !page._lineMode
                    log:            waterLog
                    rangeMin:       page._filterMin
                    rangeMax:       page._filterMax
                    columnCount:    page._heatmapColumns
                    onHoverChanged: (rowName, timeText, valueText) => {
                        heatmapHover.text = rowName + "  " + timeText + "  " + valueText
                    }
                }

                // 折线图悬停面板
                Rectangle {
                    id:                     hoverPanel
                    visible:                page._lineMode && (page._hoverX >= 0)
                    color:                  qgcPal.window
                    border.color:           qgcPal.text
                    border.width:           1
                    radius:                 ScreenTools.defaultBorderRadius
                    width:                  hoverColumn.implicitWidth + ScreenTools.defaultFontPixelWidth
                    height:                 hoverColumn.implicitHeight + ScreenTools.defaultFontPixelHeight * 0.5
                    anchors.right:          parent.right
                    anchors.top:            parent.top
                    anchors.margins:        ScreenTools.defaultFontPixelWidth * 0.5

                    Column {
                        id:                     hoverColumn
                        anchors.centerIn:       parent
                        spacing:                ScreenTools.defaultFontPixelHeight * 0.1

                        QGCLabel {
                            text:   qsTr("Time:") + " " + page.timeText(page._hoverX)
                            font.bold: true
                        }
                        Repeater {
                            model: page._hoverRows
                            Row {
                                spacing: ScreenTools.defaultFontPixelWidth * 0.5
                                Rectangle {
                                    width:  ScreenTools.defaultFontPixelHeight * 0.6
                                    height: width
                                    color:  modelData.color
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                QGCLabel { text: modelData.name + "：" + modelData.value }
                            }
                        }
                    }
                }

                // 热力图悬停提示
                QGCLabel {
                    id:                 heatmapHover
                    visible:            !page._lineMode && (text !== "")
                    color:              qgcPal.text
                    anchors.left:       parent.left
                    anchors.bottom:     parent.bottom
                    anchors.margins:    ScreenTools.defaultFontPixelWidth * 0.5
                }
            }

            // ---------------- 图例 ----------------
            Flow {
                id:                 legendFlow
                Layout.fillWidth:   true
                spacing:            ScreenTools.defaultFontPixelWidth
                visible:            waterLog.loaded

                Repeater {
                    id: legendRepeater
                    model: []

                    Row {
                        spacing: ScreenTools.defaultFontPixelWidth * 0.3
                        Rectangle {
                            width:  ScreenTools.defaultFontPixelHeight * 0.7
                            height: width
                            color:  modelData.color
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        QGCLabel {
                            text:   modelData.name + (page._lineMode ? (modelData.right ? qsTr(" (right axis)") : qsTr(" (left axis)")) : "")
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
    }
}
