import QtQuick
import QtGraphs

import QGroundControl
import QGroundControl.Controls

/// 单张水质折线图（基于 QtGraphs）。
/// 上层页面用两张这样的图（左轴组 / 右轴组）来呈现“双 Y 轴”，两张图共享同一条时间轴。
Item {
    id: control

    /// 鼠标悬停位置（X 轴值，单位秒）
    signal hoverXChanged(real x)
    /// 用户拖拽框选后请求的时间缩放范围
    signal zoomRequested(real minX, real maxX)

    /// 绘图区像素宽度（上层据此决定降采样点数）
    readonly property real plotWidth: Math.max(1, _chart.plotArea.width)

    property var  _seriesByName: ({})
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
    }

    /// 设置某个参数的曲线（不存在时创建，存在时复用后重新填点）
    function setSeriesPoints(name, color, points, minY, maxY) {
        let series = _seriesByName[name]
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
            _seriesByName[name] = series
        }
        series.color = color
        for (let i = 0; i < points.length; i++) {
            series.append(points[i].x, points[i].y)
        }
        if (points.length === 0) {
            return
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
            return
        }
        if ((_maxY - _minY) < 1e-9) {
            _maxY = _minY + 1
        }
        const padding = (_maxY - _minY) * 0.05
        yAxis.min = _minY - padding
        yAxis.max = _maxY + padding
    }

    /// 移除未在 names 里的曲线，其余曲线先清空（等 setSeriesPoints 重新填点）
    function clearSeries(names) {
        for (const name in _seriesByName) {
            const series = _seriesByName[name]
            if (names.indexOf(name) < 0) {
                _chart.removeSeries(series)
                series.destroy()
                delete _seriesByName[name]
            } else {
                series.clear()
            }
        }
    }

    function setAxisRange(minX, maxX) {
        if (maxX <= minX) {
            return
        }
        xAxis.min = minX
        xAxis.max = maxX
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

    /// 秒 -> "HH:MM:SS"
    function _timeText(seconds) {
        if (isNaN(seconds)) {
            return ""
        }
        const total = Math.max(0, Math.floor(seconds))
        const h = Math.floor(total / 3600)
        const m = Math.floor(total / 60) % 60
        const s = total % 60
        function two(v) { return v < 10 ? "0" + v : String(v) }
        return two(h) + ":" + two(m) + ":" + two(s)
    }

    Component {
        id: lineSeriesComponent
        LineSeries { }
    }

    GraphsView {
        id:                 _chart
        anchors.fill:       parent
        marginTop:          0
        marginRight:        0
        marginBottom:       0
        marginLeft:         0

        theme: GraphsTheme {
            colorScheme:                qgcPal.globalTheme === QGCPalette.Light ? GraphsTheme.ColorScheme.Light : GraphsTheme.ColorScheme.Dark
            backgroundColor:            qgcPal.windowShadeDark
            backgroundVisible:          true
            plotAreaBackgroundColor:    qgcPal.windowShadeDark
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
                            return isNaN(seconds) ? parent.text : control._timeText(seconds)
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

    // 框选矩形
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
            control._hoverPixelX = mouse.x
            if (pressed && (pressX >= 0)) {
                selectionRect.x = Math.min(pressX, mouse.x)
                selectionRect.width = Math.abs(mouse.x - pressX)
                selectionRect.visible = true
            }
            control.hoverXChanged(control._pixelToX(mouse.x))
        }

        onPressed: (mouse) => {
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

        onExited: control._hoverPixelX = -1
    }
}
