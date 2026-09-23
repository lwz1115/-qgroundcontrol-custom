pragma ComponentBehavior: Bound

import QtQuick
import QtGraphs

import QGroundControl
import QGroundControl.Controls

import "WaterQualityUtils.js" as WQUtils

/// 单张水质折线图（基于 QtGraphs）。
/// 上层页面只显示一个参数，曲线与 Y 轴都用真实数值（不再做归一化）。
Item {
    id: control

    /// 鼠标悬停位置（X 轴值，单位秒）
    signal hoverXChanged(real x)
    /// 用户拖拽框选后请求的时间缩放范围
    signal zoomRequested(real minX, real maxX)
    /// 绘图区几何（位置或宽度）变化：上层据此对齐两张图、并按新宽度重新降采样
    signal plotAreaGeometryChanged()

    /// 绘图区像素宽度（上层据此决定降采样点数）。
    /// plotArea 是 QtGraphs 的内部对象，宽度变化没有 notify 信号，
    /// 用 plotArea.width 写绑定会永远卡在第一次取到的值上（布局完成前还可能只是回退值），
    /// 所以改成主动刷新，见 _syncPlotWidth()。
    property real plotWidth: 100

    /// 绘图区左边界（像素）
    readonly property real plotAreaX: _chart.plotArea.x

    /// X 轴标签是否用短格式（HH:MM）：在 setAxisRange 里按跨度定下来
    property bool _shortAxisLabels: false
    /// 上一次同步到的绘图区左边界，用于判断是否需要通知上层
    property real _lastPlotAreaX: -1

    property var  _series:        null   ///< 全程复用同一条曲线（切换参数只换数据，不建/销对象）
    property var  _singlePoints: []   ///< 区间内只有 1 个采样点的参数（[{x, y, color}]），另外画成圆点
    property real _hoverPixelX:  -1
    property real _minY:         NaN
    property real _maxY:         NaN

    // ---------------------------------------------------------------------
    // 供上层调用
    // ---------------------------------------------------------------------

    /// 开始一轮刷新（重置 Y 轴范围统计）
    function beginUpdate() {
        _minY = NaN
        _maxY = NaN
        _singlePoints = []
        _syncPlotWidth()
    }

    /// 设置当前曲线的数据。
    /// 注意：这里始终复用同一条 LineSeries —— 早先的写法是「按参数名建多条，切换时
    /// removeSeries + destroy()」，destroy() 会在渲染线程仍持有该对象时立刻销毁它，
    /// 导致切换参数必崩。单参数显示本来也只需要一条曲线，改为复用后彻底消除该问题。
    function setSeriesPoints(name, color, points, minY, maxY) {
        let series = _series
        if (!series) {
            series = lineSeriesComponent.createObject(_chart, {
                color:   color,
                width:   2,
                axisX:   xAxis,
                axisY:   yAxis
            })
            if (!series) {
                return
            }
            _chart.addSeries(series)
            _series = series
        }
        series.clear()
        series.color = color
        for (let i = 0; i < points.length; i++) {
            series.append(points[i].x, points[i].y)
        }
        if (points.length === 0) {
            return
        }
        if (points.length === 1) {
            // 单个点不成线（QtGraphs 不会画出任何东西），单独记下来用圆点标出
            _singlePoints = _singlePoints.concat([{ x: points[0].x, y: points[0].y, color: color }])
        }
        if (isNaN(_minY) || (minY < _minY)) {
            _minY = minY
        }
        if (isNaN(_maxY) || (maxY > _maxY)) {
            _maxY = maxY
        }
    }

    /// 结束一轮刷新：按本轮的数值范围设置 Y 轴
    function endUpdate() {
        if (isNaN(_minY) || isNaN(_maxY)) {
            yAxis.min = 0
            yAxis.max = 1
            _syncPlotWidth()
            return
        }
        if ((_maxY - _minY) < 1e-9) {
            _maxY = _minY + 1
        }
        const padding = (_maxY - _minY) * 0.05
        yAxis.min = _minY - padding
        yAxis.max = _maxY + padding
        // 一轮填完布局已稳定，把绘图区几何同步给上层
        _syncPlotWidth()
    }

    /// 清空曲线数据（切换参数 / 重新导入时调用）
    /// 只清数据、不删对象：曲线全程复用（见 setSeriesPoints 的说明）。
    /// 形参 names 保留是为了不改动调用处签名，这里不再按名字区分曲线。
    function clearSeries(names) {
        if (_series) {
            _series.clear()
        }
    }

    function setAxisRange(minX, maxX) {
        if (isNaN(minX) || isNaN(maxX)) {
            return
        }
        let span = maxX - minX
        if (!(span > 0)) {
            // 数据只有一个时间点（或全部时间相同）：给一个最小跨度，否则轴不会更新
            span = 1
        }
        // 先定范围再定刻度间隔：交给轴自动算会给出十几个刻度，时间标签会挤成一团。
        // 刻度只落在 tickInterval 的整数倍上，而数据结束时间（如 23:55）通常不是整数倍，
        // 右端刻度会被画到轴外看不见（表现就是 24:00 缺失），所以把轴上限对齐到刻度整数倍。
        const interval = WQUtils.niceTickInterval(span)
        xAxis.tickInterval = interval
        xAxis.min = minX
        xAxis.max = minX + Math.ceil(span / interval) * interval
        // 显式更新标签格式：labelDelegate 的文本绑定依赖它，
        // 只改 min/max 时标签有可能停在旧的 HH:MM:SS 样式上
        _shortAxisLabels = (span >= 3600)
        _syncPlotWidth()
    }

    /// 清除数据（导入失败、数据被清空时调用）
    /// 同样只清数据、不销毁曲线对象（destroy() 会与渲染侧竞争导致闪退）
    function clearAll() {
        if (_series) {
            _series.clear()
        }
        _minY = NaN
        _maxY = NaN
        _hoverPixelX = -1
        _singlePoints = []
    }

    /// 回到“未导入数据”时的空坐标系：时间轴按 1 小时铺开，数值轴 0..1
    function resetToEmpty() {
        clearAll()
        yAxis.min = 0
        yAxis.max = 1
        // 空坐标系固定是 1 小时跨度，刻度间隔要一起重置，
        // 否则会沿用上次数据的大间隔，1 小时里只剩 1~2 个刻度
        xAxis.min = 0
        xAxis.max = 3600
        xAxis.tickInterval = WQUtils.niceTickInterval(3600)
        _shortAxisLabels = false
        _syncPlotWidth()
    }

    // ---------------------------------------------------------------------
    // 像素 <-> 时间值换算（与 Log Viewer 一致：用绘图区做线性映射）
    // ---------------------------------------------------------------------
    function _pixelToX(pixelX) {
        const plotX = _chart.plotArea.x
        const plotW = _chart.plotArea.width
        if ((plotW <= 0) || (xAxis.max <= xAxis.min)) {
            return xAxis.min
        }
        const clamped = Math.max(plotX, Math.min(plotX + plotW, pixelX))
        return xAxis.min + ((clamped - plotX) / plotW) * (xAxis.max - xAxis.min)
    }

    function _xToPixel(x) {
        const plotX = _chart.plotArea.x
        const plotW = _chart.plotArea.width
        if ((plotW <= 0) || (xAxis.max <= xAxis.min)) {
            return plotX
        }
        const ratio = (x - xAxis.min) / (xAxis.max - xAxis.min)
        return plotX + Math.max(0, Math.min(plotW, ratio * plotW))
    }

    /// 数值 -> 绘图区像素 Y（用于给单点标记定位）
    function _valueToPixelY(value) {
        const plotY = _chart.plotArea.y
        const plotH = _chart.plotArea.height
        if ((plotH <= 0) || (yAxis.max <= yAxis.min) || isNaN(value)) {
            return plotY
        }
        const ratio = (value - yAxis.min) / (yAxis.max - yAxis.min)
        return plotY + plotH - Math.max(0, Math.min(1, ratio)) * plotH
    }

    /// 同步绘图区宽度与左边界，并在发生变化时通知上层。
    /// 布局还没完成时 plotArea 宽度还是 0，这里给一个回退值，避免上层只取到 1 个降采样点。
    function _syncPlotWidth() {
        const rawWidth = _chart.plotArea.width
        const plotX    = _chart.plotArea.x
        const newWidth = (rawWidth > 8) ? rawWidth : Math.max(100, width * 0.8)
        const changed  = (Math.abs(newWidth - plotWidth) > 0.5)
                      || (_lastPlotAreaX < 0)
                      || (Math.abs(plotX - _lastPlotAreaX) > 0.5)
        plotWidth      = newWidth
        _lastPlotAreaX = plotX
        if (changed) {
            plotAreaGeometryChanged()
        }
    }

    /// 鼠标像素是否落在绘图区内：坐标轴 / 标签那一片不应该触发悬停与框选
    function _insidePlotArea(pixelX) {
        const plotX = _chart.plotArea.x
        const plotW = _chart.plotArea.width
        return (plotW > 0) && (pixelX >= plotX) && (pixelX <= (plotX + plotW))
    }

    /// 浅拷贝曲线表（避免在 property var 的 map 上直接增删 key）
    /// 曲线改为单条复用后已无调用处，保留会误导后来者，故删除
    Component.onCompleted: _syncPlotWidth()
    onWidthChanged:        _syncPlotWidth()
    onHeightChanged:       _syncPlotWidth()

    // plotArea 是 QtGraphs 内部对象，它重建 / 变尺寸时会发这个信号
    Connections {
        target: _chart

        function onPlotAreaChanged() {
            control._syncPlotWidth()
        }
    }

    Component {
        id: lineSeriesComponent
        LineSeries { }
    }

    GraphsView {
        id:                 _chart
        anchors.fill:       parent
        marginTop:          0
        marginBottom:       0
        marginLeft:         0
        // 给最右侧的时间刻度留出位置：标签以刻度为中心绘制，不预留会被容器裁掉（表现就是只显示 "24"）
        marginRight:        ScreenTools.defaultFontPixelWidth * 1.5

        theme: GraphsTheme {
            colorScheme:                qgcPal.globalTheme === QGCPalette.Light ? GraphsTheme.ColorScheme.Light : GraphsTheme.ColorScheme.Dark
            // 绘图区跟页面底色一致，不要再叠一层灰：windowShadeDark 在亮色主题下也偏灰，
            // 和页面一起看会很脏（LogViewer 用的是 windowShadeDark，这里是刻意不同的）
            backgroundColor:            qgcPal.window
            backgroundVisible:          false
            plotAreaBackgroundColor:    qgcPal.window
            grid.mainColor:             Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.25)
            grid.subColor:              Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.12)
            grid.mainWidth:             1
            labelBackgroundVisible:     false
            labelTextColor:             qgcPal.text
            axisXLabelFont.family:      ScreenTools.fixedFontFamily
            axisXLabelFont.pointSize:   ScreenTools.smallFontPointSize
            axisYLabelFont.family:      ScreenTools.fixedFontFamily
            axisYLabelFont.pointSize:   ScreenTools.smallFontPointSize
        }

        axisX: ValueAxis {
            id:         xAxis
            min:        0
            max:        1
            labelFormat: "%.0f"

            labelDelegate: Component {
                Item {
                    property string text: ""   // 由坐标轴填入原始秒数

                    Text {
                        anchors.centerIn:   parent
                        color:              _chart.theme.labelTextColor
                        font:               _chart.theme.axisXLabelFont
                        horizontalAlignment: Text.AlignHCenter
                        text: {
                            const seconds = parseFloat(parent.text)
                            if (isNaN(seconds)) {
                                return parent.text
                            }
                            return control._shortAxisLabels ? WQUtils.timeTextShort(seconds)
                                                            : WQUtils.timeText(seconds)
                        }
                    }
                }
            }
        }

        axisY: ValueAxis {
            id:         yAxis
            min:        0
            max:        1
            labelFormat: "%.2f"
        }
    }

    // 单点标记：区间内只有一个采样点时用圆点表示，否则看起来像没数据
    Repeater {
        model: control._singlePoints

        Rectangle {
            // 开 Bound 后 delegate 的 modelData 必须显式声明，否则运行时根本取不到
            required property var modelData

            width:  ScreenTools.defaultFontPixelHeight * 0.5
            height: width
            radius: width / 2
            color:  modelData.color
            x:      control._xToPixel(modelData.x) - width / 2
            y:      control._valueToPixelY(modelData.y) - height / 2
        }
    }

    // 悬停竖线
    Rectangle {
        x:              control._hoverPixelX
        width:          1
        height:         _chart.plotArea.height
        y:              _chart.plotArea.y
        color:          qgcPal.text
        opacity:        0.5
        visible:        control._hoverPixelX >= 0
    }

    // 框选矩形。
    // 坐标系：_chart 用 anchors.fill 铺满本控件，selectionRect 是它的兄弟节点，
    // 所以 MouseArea 的 mouse.x 和 _chart.plotArea.x 处在同一坐标系里，可以直接比较。
    Rectangle {
        id:             selectionRect
        visible:        false
        y:              _chart.plotArea.y
        height:         _chart.plotArea.height
        color:          qgcPal.text
        opacity:        0.15
        border.color:   qgcPal.text
        border.width:   1
    }

    MouseArea {
        anchors.fill:   parent
        hoverEnabled:   true

        property real pressX: -1

        onPositionChanged: (mouse) => {
            // 只在绘图区内响应：坐标轴 / 标签那一片不该触发悬停与框选
            const inside = control._insidePlotArea(mouse.x)
            control._hoverPixelX = inside ? mouse.x : -1
            if (inside && pressed && (pressX >= 0)) {
                selectionRect.x = Math.min(pressX, mouse.x)
                selectionRect.width = Math.abs(mouse.x - pressX)
                selectionRect.visible = true
            }
            control.hoverXChanged(inside ? control._pixelToX(mouse.x) : -1)
        }

        onPressed: (mouse) => {
            // 起手不在绘图区内就不进入框选状态
            if (!control._insidePlotArea(mouse.x)) {
                pressX = -1
                selectionRect.visible = false
                return
            }
            pressX = mouse.x
            selectionRect.visible = false
        }

        onReleased: (mouse) => {
            if (selectionRect.visible && (selectionRect.width > 8)) {
                const left  = control._pixelToX(selectionRect.x)
                const right = control._pixelToX(selectionRect.x + selectionRect.width)
                control.zoomRequested(left, right)
            }
            selectionRect.visible = false
            pressX = -1
        }

        onExited: {
            // 鼠标移出时必须顺带通知上层，否则悬停面板会一直挂着
            control._hoverPixelX = -1
            control.hoverXChanged(-1)
        }
    }
}
