pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

import "WaterQualityUtils.js" as WQUtils

/// 水质监测：导入 Excel(.xlsx)/CSV 表格，用折线图看单个参数随时间的变化，
/// 或在地图上把监测路径按参数数值着色（热力路径）。
///
/// 表格约定（自适应）：表头行按列名关键字自动定位（不必在第 1 行），
/// 认「时间 / 经度 / 纬度 / 电导率 / pH / 溶解氧 / 铵离子 / 叶绿素 / TAL-PC / 浊度」（含常见英文别名），
/// 其它列忽略。时间轴与板载日志一致，统一用“相对首条记录的秒数”，显示成 HH:MM:SS。
///
/// 两个视图各自只看一个参数，导入后默认都是第一个参数，之后由用户手动选择。
AnalyzePage {
    id:                 page
    pageComponent:      pageComponent
    pageDescription:    qsTr("Import water quality monitoring data (Excel .xlsx or .csv) and view one parameter at a time as a line chart, or as a colored monitoring path on the map.")
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
    property bool   _lineMode:      true          ///< true: 折线图；false: 地图热力路径
    property string _lineParameter: ""            ///< 折线图显示的参数
    property string _mapParameter:  ""            ///< 地图着色的参数
    property real   _filterMin:     0             ///< 时间筛选起点（秒）
    property real   _filterMax:     1             ///< 时间筛选终点（秒）
    property real   _zoomMin:       0             ///< 当前显示的时间范围
    property real   _zoomMax:       1
    property real   _hoverX:        -1            ///< 悬停位置（X 轴值，-1 表示不显示）
    property var    _hoverRows:     []            ///< 悬停面板内容 [{name, value}]

    /// 折线图只有一条曲线，固定用这个颜色
    readonly property color _lineColor: "#1E88E5"

    /// 参数名本地化：解析器返回的规范名（电导率 / pH / …）是内部标识符、不参与翻译，
    /// 这里映射成界面显示名 —— 中文语言显示中文，英文语言显示英文。
    function parameterDisplayName(canonicalName) {
        switch (canonicalName) {
        case "电导率":  return qsTr("Conductivity")
        case "pH":      return qsTr("pH")
        case "溶解氧":  return qsTr("Dissolved Oxygen")
        case "铵离子":  return qsTr("Ammonium")
        case "叶绿素":  return qsTr("Chlorophyll")
        case "TAL-PC":  return qsTr("Phycocyanin")
        case "浊度":    return qsTr("Turbidity")
        default:        return canonicalName
        }
    }

    /// 下拉框用的显示名数组，顺序与 waterLog.parameterNames 严格一一对应
    readonly property var _parameterDisplayNames: {
        const names = waterLog.parameterNames
        const out = []
        for (let i = 0; i < names.length; i++) {
            out.push(parameterDisplayName(names[i]))
        }
        return out
    }

    // 注意：id 只在声明它的组件内有效，page 的函数访问不到 pageComponent 里的 id，
    // 因此图表刷新与时间输入框同步都改成“page 发信号、页面组件自己处理”。
    /// 请求页面组件重建图表
    signal chartsRefreshRequested()
    /// 请求页面组件回到空坐标系
    signal chartsResetRequested()
    /// 请求页面组件把时间输入框刷成指定范围
    signal timeFieldsSyncRequested(real minSeconds, real maxSeconds)
    /// 请求页面组件把参数下拉框刷成当前选中的参数
    signal parameterSelectionSyncRequested()

    // ---------------------------------------------------------------------
    // 工具函数
    // ---------------------------------------------------------------------

    /// 秒 -> "HH:MM:SS"（相对首条记录）；无法解析时给占位符
    function timeText(seconds) {
        if (isNaN(seconds)) {
            return "--"
        }
        return WQUtils.timeText(seconds)
    }

    /// 起始时间是否可接受：必须在数据时间范围内，且小于当前显示区间的右端
    function isValidStartTime(seconds) {
        return !isNaN(seconds) && (seconds >= _filterMin) && (seconds < _zoomMax)
    }

    /// 结束时间是否可接受：必须在数据时间范围内，且大于当前显示区间的左端
    function isValidEndTime(seconds) {
        return !isNaN(seconds) && (seconds <= _filterMax) && (seconds > _zoomMin)
    }

    /// "HH:MM:SS" 或纯秒 -> 秒；解析失败返回 NaN
    function textToSeconds(text) {
        const t = String(text).trim()
        if (t === "") {
            return NaN
        }
        if (t.indexOf(":") >= 0) {
            const parts = t.split(":")
            let seconds = 0
            for (let i = 0; i < parts.length; i++) {
                const v = Number(parts[i])
                if (isNaN(v)) {
                    return NaN
                }
                seconds = seconds * 60 + v
            }
            return seconds
        }
        const value = Number(t)
        return isNaN(value) ? NaN : value
    }

    function _applyFilters() {
        if (!waterLog.loaded) {
            return
        }
        const minTime = waterLog.minTime
        let maxTime = waterLog.maxTime
        if (!(maxTime > minTime)) {
            // 只有一条记录（时间列全部相同）时给一个最小跨度，否则坐标轴会退化
            maxTime = minTime + 1
        }
        _filterMin = minTime
        _filterMax = maxTime
        _zoomMin   = minTime
        _zoomMax   = maxTime
        // 输入框里显示的是「当前显示范围」（zoom），不要传筛选范围
        timeFieldsSyncRequested(_zoomMin, _zoomMax)
    }

    function importFile(file) {
        _hoverX = -1
        _hoverRows = []

        if (waterLog.loadFile(file)) {
            // 折线图和地图都默认显示第一个参数，之后由用户手动选择
            const firstParameter = (waterLog.parameterNames.length > 0) ? waterLog.parameterNames[0] : ""
            _lineParameter = firstParameter
            _mapParameter  = firstParameter
            parameterSelectionSyncRequested()
            _applyFilters()
            chartsRefreshRequested()
            return
        }

        // 导入失败时数据源已清空，界面也要回到空坐标系，
        // 时间范围同样要归零，否则上一次的 zoom / filter 会残留到下一次导入
        _lineParameter = ""
        _mapParameter  = ""
        parameterSelectionSyncRequested()
        _filterMin = 0
        _filterMax = 1
        _zoomMin   = 0
        _zoomMax   = 1
        chartsResetRequested()
    }

    function selectLineParameter(name) {
        if ((name === "") || (name === _lineParameter)) {
            return
        }
        _lineParameter = name
        chartsRefreshRequested()
    }

    function selectMapParameter(name) {
        if ((name === "") || (name === _mapParameter)) {
            return
        }
        _mapParameter = name
        chartsRefreshRequested()
    }

    /// 悬停：取当前折线参数在离鼠标最近时间点上的数值
    /// （sampleAt 内部是二分查找，不会因鼠标移动而卡顿）
    function updateHover(xValue) {
        if (!waterLog.loaded || (_lineParameter === "") || (xValue < 0)) {
            // 鼠标移出图表：收起悬停面板（否则 sampleAt 会二分到第 0 条记录）
            _hoverX = -1
            _hoverRows = []
            return
        }
        _hoverX = xValue

        const sample = waterLog.sampleAt(_lineParameter, xValue)
        // 空 map 时 sample.y 是 undefined；C++ 侧也可能给回 null，
        // 而 Number(null) 是 0，不显式挡掉就会显示成 0.000
        const hasValue = (sample != null) && (sample.y != null) && !isNaN(sample.y)
        _hoverRows = [{ name: parameterDisplayName(_lineParameter), value: hasValue ? Number(sample.y).toFixed(3) : "--" }]
    }

    // ---------------------------------------------------------------------
    // 导入文件对话框
    // ---------------------------------------------------------------------
    QGCFileDialog {
        id:             importDialog
        title:          qsTr("Select water quality data file")
        folder:         QGroundControl.settingsManager.appSettings.savePath.rawValue
        nameFilters:    [ qsTr("Excel workbook (*.xlsx)"), qsTr("CSV table (*.csv)"), qsTr("All Files (*)") ]
        onAcceptedForLoad: (file) => page.importFile(file)
    }

    // ---------------------------------------------------------------------
    // 页面内容
    // ---------------------------------------------------------------------
    Component {
        id: pageComponent

        // AnalyzePage 里的 pageLoader 是没有锚定、没有尺寸的裸 Loader，item 用 anchors.fill: parent
        // 会退化成自引用（Loader 的尺寸又取自 item 的隐式尺寸），整个布局就塌缩到内容高度。
        // 这里跟 LogViewerPage 一致，直接取 AnalyzePage 留给我们的区域；
        // availableHeight 已经扣过标题栏高度，不要再自己减 pageDescription 的高度。
        ColumnLayout {
            id:             contentLayout
            width:          page.availableWidth
            height:         page.availableHeight
            spacing:        ScreenTools.defaultFontPixelHeight * 0.5

            // 这里的函数可以访问本组件内部的 id（page 里的函数不行），由 page 的信号驱动
            Connections {
                target: page

                function onChartsRefreshRequested() { refreshCharts() }
                function onChartsResetRequested()   { resetCharts() }
                function onTimeFieldsSyncRequested(minSeconds, maxSeconds) {
                    startField.text = page.timeText(minSeconds)
                    endField.text = page.timeText(maxSeconds)
                }
                function onParameterSelectionSyncRequested() {
                    lineParameterCombo.currentIndex = Math.max(0, waterLog.parameterNames.indexOf(page._lineParameter))
                    mapParameterCombo.currentIndex  = Math.max(0, waterLog.parameterNames.indexOf(page._mapParameter))
                }
            }

            // 页面一实例化就先把空坐标系画出来（未导入数据时也有网格、坐标轴、占位提示）
            Component.onCompleted: resetCharts()

            /// 按当前参数 / 时间范围重建两个视图
            function refreshCharts() {
                if (!waterLog.loaded) {
                    resetCharts()
                    return
                }
                fillLineChart()
                mapPath.refresh()
            }

            /// 绘图区几何变化（宽度变了）后按新的像素宽度重新降采样。
            /// 必须延后一拍，否则会在「设轴范围 → 信号 → 再填」的调用栈里递归。
            function handlePlotAreaGeometryChanged() {
                Qt.callLater(fillLineChart)
            }

            /// 回到空坐标系（未导入数据 / 导入失败时调用）
            function resetCharts() {
                lineChart.resetToEmpty()
                mapPath.refresh()
                startField.text = page.timeText(0)
                endField.text = page.timeText(0)
            }

            /// 用当前选中的参数填充折线图
            function fillLineChart() {
                const name = page._lineParameter
                lineChart.beginUpdate()
                if (name === "") {
                    lineChart.clearSeries([])
                    lineChart.endUpdate()
                    lineChart.setAxisRange(page._zoomMin, page._zoomMax)
                    return
                }

                lineChart.clearSeries([name])
                const points = waterLog.samplesForParameter(name, page._zoomMin, page._zoomMax,
                                                            Math.max(1, Math.floor(lineChart.plotWidth)))

                // Y 轴范围必须按当前显示区间内的点算，用全量极值会把放大后的曲线压扁
                let minValue = NaN
                let maxValue = NaN
                for (let i = 0; i < points.length; i++) {
                    const value = points[i].y
                    if (isNaN(value)) {
                        continue
                    }
                    if (isNaN(minValue) || (value < minValue)) {
                        minValue = value
                    }
                    if (isNaN(maxValue) || (value > maxValue)) {
                        maxValue = value
                    }
                }

                lineChart.setSeriesPoints(name, page._lineColor, points, minValue, maxValue)
                lineChart.endUpdate()
                lineChart.setAxisRange(page._zoomMin, page._zoomMax)
            }

            // ---------------- 工具条 ----------------
            RowLayout {
                Layout.fillWidth:    true
                // 描述文字与按钮之间留一点呼吸空间
                Layout.topMargin:    ScreenTools.defaultFontPixelHeight
                // 右上角的「弹出」图标是浮在页面之上的（图标本身有 2 个字高），这里给它让足位置，
                // 否则「共 N 条记录」会被压在图标下面
                Layout.rightMargin:  ScreenTools.defaultFontPixelHeight * 4
                spacing:             ScreenTools.defaultFontPixelWidth * 1.5

                QGCButton {
                    text:    qsTr("Import Excel")
                    // QGCFileDialog 没有 open()：必须用 openForLoad()，否则点击后什么都不会发生
                    onClicked: importDialog.openForLoad()
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

            // ---------------- 视图类型 + 参数选择 + 时间范围 ----------------
            // 没有数据时也保留视图类型按钮，空坐标系同样能切换折线图 / 地图
            RowLayout {
                Layout.fillWidth: true
                spacing:          ScreenTools.defaultFontPixelWidth

                QGCRadioButton {
                    id:      lineRadio
                    text:    qsTr("Line Chart")
                    checked: page._lineMode
                    onClicked: page._lineMode = true
                }
                QGCRadioButton {
                    text:    qsTr("Map Heat Path")
                    checked: !page._lineMode
                    onClicked: page._lineMode = false
                }

                Rectangle {
                    Layout.preferredWidth:  1
                    Layout.fillHeight:      true
                    color:                  qgcPal.text
                    opacity:                0.3
                    visible:                waterLog.loaded
                }

                QGCLabel {
                    text:       qsTr("Parameter:")
                    visible:    waterLog.loaded
                }

                QGCComboBox {
                    id:                 lineParameterCombo
                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 12
                    visible:            waterLog.loaded && page._lineMode
                    model:              page._parameterDisplayNames
                    // 用户改选后 page 会刷新图表；这里不用绑定 currentIndex，
                    // 导入新文件时由 parameterSelectionSyncRequested 统一同步。
                    // 模型是本地化显示名，回传时必须换算回规范名（内部标识符）
                    onActivated: (index) => page.selectLineParameter(waterLog.parameterNames[index])
                }

                QGCComboBox {
                    id:                 mapParameterCombo
                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 12
                    visible:            waterLog.loaded && !page._lineMode
                    model:              page._parameterDisplayNames
                    onActivated: (index) => page.selectMapParameter(waterLog.parameterNames[index])
                }

                QGCLabel {
                    text:       qsTr("Time range:")
                    visible:    waterLog.loaded
                }

                QGCTextField {
                    id:                     startField
                    Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 10
                    visible:                waterLog.loaded
                    onEditingFinished: {
                        const seconds = page.textToSeconds(text)
                        if (page.isValidStartTime(seconds)) {
                            page._zoomMin = seconds
                            refreshCharts()
                        } else {
                            // 回填当前显示范围（_zoom），而不是筛选范围（_filter）
                            text = page.timeText(page._zoomMin)
                        }
                    }
                }

                QGCLabel {
                    text:       qsTr("to")
                    visible:    waterLog.loaded
                }

                QGCTextField {
                    id:                     endField
                    Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 10
                    visible:                waterLog.loaded
                    onEditingFinished: {
                        const seconds = page.textToSeconds(text)
                        if (page.isValidEndTime(seconds)) {
                            page._zoomMax = seconds
                            refreshCharts()
                        } else {
                            // 回填当前显示范围（_zoom），而不是筛选范围（_filter）
                            text = page.timeText(page._zoomMax)
                        }
                    }
                }

                QGCButton {
                    text:       qsTr("Reset Zoom")
                    // 折线图和地图都用 _zoomMin/_zoomMax，但只在真的缩放过时才显示，
                    // 否则地图下会出现一个点了也没变化的按钮
                    visible:    waterLog.loaded
                                && ((page._zoomMin > page._filterMin) || (page._zoomMax < page._filterMax))
                    onClicked: {
                        page._zoomMin = page._filterMin
                        page._zoomMax = page._filterMax
                        refreshCharts()
                    }
                }

                QGCCheckBox {
                    text:    qsTr("Remove min/max")
                    // 导入时 C++ 侧已经按这个开关算过了，这里只是让用户可以关掉 / 打开
                    visible: waterLog.loaded
                    checked: waterLog.filterExtremes
                    onToggled: {
                        waterLog.filterExtremes = checked
                        refreshCharts()
                    }
                }

                QGCLabel {
                    text:    qsTr("%1 removed").arg(waterLog.excludedSampleCount)
                    visible: waterLog.loaded && (waterLog.excludedSampleCount > 0)
                }

                Item { Layout.fillWidth: true }
            }

            // ---------------- 图表本体 ----------------
            // 窗口被压得很扁时，fillHeight 的项会一路缩到 0，图表退化成一条线、
            // GraphsView / 地图画不出来，轴标签还会溢出盖住上面的单选行
            Item {
                Layout.fillWidth:     true
                Layout.fillHeight:    true
                Layout.minimumHeight: ScreenTools.defaultFontPixelHeight * 8
                // GraphsView 的轴标签默认不裁剪，会画到上面的单选行 / 时间输入框上，
                // 连那一带的鼠标事件也一起吃掉（表现就是控件点不动），这里裁掉溢出的部分
                clip:                 true

                // 折线图：只画当前选中的参数
                QualityLineChart {
                    id:                        lineChart
                    anchors.fill:              parent
                    visible:                   page._lineMode
                    onHoverXChanged:           (x) => page.updateHover(x)
                    onPlotAreaGeometryChanged: contentLayout.handlePlotAreaGeometryChanged()
                    onZoomRequested:           (minX, maxX) => {
                        page._zoomMin = minX
                        page._zoomMax = maxX
                        startField.text = page.timeText(minX)
                        endField.text = page.timeText(maxX)
                        refreshCharts()
                    }
                }

                // 地图热力路径：按当前选中的参数给监测路径着色
                QualityMapPath {
                    id:              mapPath
                    anchors.fill:    parent
                    visible:         !page._lineMode
                    log:             waterLog
                    parameterName:   page._mapParameter
                    // 图例显示本地化名称（中文语言中文、英文语言英文）
                    parameterLabel:  page.parameterDisplayName(page._mapParameter)
                    rangeMin:        page._zoomMin
                    rangeMax:        page._zoomMax
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
                                id:                 hoverRow
                                required property var modelData
                                spacing: ScreenTools.defaultFontPixelWidth * 0.5
                                Rectangle {
                                    width:  ScreenTools.defaultFontPixelHeight * 0.6
                                    height: width
                                    color:  page._lineColor
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                QGCLabel { text: hoverRow.modelData.name + "：" + hoverRow.modelData.value }
                            }
                        }
                    }
                }
            }

            // ---------------- 图例 ----------------
            // 折线图下说明曲线颜色对应的参数
            Item {
                Layout.fillWidth:       true
                Layout.preferredHeight: legendRow.implicitHeight
                // 不设 minimumHeight：空间不够时要允许它被压缩，
                // 否则会把整个 ColumnLayout 撑出页面底部、图例被裁掉一半
                visible:                page._lineMode

                Row {
                    id:      legendRow
                    spacing: ScreenTools.defaultFontPixelWidth

                    // 占位：未导入数据时也把这一行渲染出来
                    QGCLabel {
                        visible:    !waterLog.loaded
                        text:       qsTr("Parameter legend will appear here after a file is imported")
                        opacity:    0.6
                    }

                    Rectangle {
                        visible:                waterLog.loaded
                        width:                  ScreenTools.defaultFontPixelHeight * 0.7
                        height:                 width
                        color:                  page._lineColor
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    QGCLabel {
                        visible:                waterLog.loaded
                        text:                   page.parameterDisplayName(page._lineParameter)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
