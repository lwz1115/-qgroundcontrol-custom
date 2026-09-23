import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

/// 水质实时折线图（简易版，Canvas 手绘）
///
/// · 采样点由 WaterQualityOverlay 每秒推一次，本控件只负责绘制；
/// · selectedParameter 为空串时同时画全部参数：各参数量程差好几个数量级
///   （电导率 0.3 上下、叶绿素几十），共用一根 Y 轴时小量程会被压成一条直线，
///   所以这个模式下每条曲线按自身量程归一化成 0~100%；
/// · filterExtremes 打开时先剔除每条曲线的极大值 / 极小值再绘制，
///   毛刺既不会画出来，也不会把 Y 轴量程拉偏。
Item {
    id: control

    /// [{ key, label, color }]，顺序决定图例顺序
    property var    parameterDefs:      []
    /// [{ t, values: { <key>: <数值> } }]，t 是毫秒时间戳
    property var    samples:            []
    /// 空串表示显示全部参数
    property string selectedParameter:  ""
    /// 剔除极大值 / 极小值后再显示
    property bool   filterExtremes:     true
    property int    extremeFilterCount: 1
    /// 采样或选项变化时自增，用来触发重绘（Canvas 不会自己跟着数据刷新）
    property int    revision:           0

    readonly property bool _singleMode: selectedParameter.length > 0

    onRevisionChanged:           chartCanvas.requestPaint()
    onSamplesChanged:            chartCanvas.requestPaint()
    onSelectedParameterChanged:  chartCanvas.requestPaint()
    onFilterExtremesChanged:     chartCanvas.requestPaint()
    onExtremeFilterCountChanged: chartCanvas.requestPaint()
    onParameterDefsChanged:      chartCanvas.requestPaint()

    Canvas {
        id: chartCanvas
        anchors.fill: parent
        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()
        onPaint:         control._paintChart(ctx)
    }

    /// 每条曲线的显示数据：{ key, label, color, points: [{x, y}], min, max }
    function _buildSeries() {
        const seriesList = []
        if (!samples || (samples.length === 0)) {
            return seriesList
        }

        for (const def of parameterDefs) {
            if (_singleMode && (def.key !== selectedParameter)) {
                continue
            }

            const rawValues = []
            for (const sample of samples) {
                const value = sample.values[def.key]
                rawValues.push(isFinite(value) ? value : NaN)
            }

            const excluded = _excludedIndices(rawValues)

            const points = []
            let minValue = NaN
            let maxValue = NaN
            for (let i = 0; i < rawValues.length; i++) {
                const value = rawValues[i]
                if (!isFinite(value) || (excluded[i] === true)) {
                    continue
                }
                points.push({ x: samples[i].t, y: value })
                if (!isFinite(minValue) || (value < minValue)) {
                    minValue = value
                }
                if (!isFinite(maxValue) || (value > maxValue)) {
                    maxValue = value
                }
            }

            seriesList.push({ key: def.key, label: def.label, color: def.color,
                              points: points, min: minValue, max: maxValue })
        }
        return seriesList
    }

    /// 需要剔除的采样点下标（稀疏数组，下标即被剔除的位置）
    function _excludedIndices(values) {
        const excluded = []
        if (!filterExtremes) {
            return excluded
        }

        // 最新一个点还在刷新，不参与极值评选：否则数值一旦处于窗口极值，
        // 曲线末端会每秒消失一次，看起来像在跳
        const ranked = []
        for (let i = 0; i < (values.length - 1); i++) {
            if (isFinite(values[i])) {
                ranked.push(i)
            }
        }
        ranked.sort((lhs, rhs) => values[lhs] - values[rhs])

        const dropCount = Math.min(extremeFilterCount, Math.max(0, Math.floor((ranked.length - 1) / 2)))
        for (let i = 0; i < dropCount; i++) {
            excluded[ranked[i]] = true
            excluded[ranked[ranked.length - 1 - i]] = true
        }
        return excluded
    }

    function _formatValue(value) {
        const magnitude = Math.abs(value)
        if (magnitude >= 1000) {
            return value.toFixed(0)
        }
        if (magnitude >= 100) {
            return value.toFixed(1)
        }
        if (magnitude >= 1) {
            return value.toFixed(2)
        }
        if (magnitude >= 0.01) {
            return value.toFixed(3)
        }
        return value.toExponential(1)
    }

    function _paintChart(ctx) {
        const canvasWidth  = chartCanvas.width
        const canvasHeight = chartCanvas.height
        ctx.clearRect(0, 0, canvasWidth, canvasHeight)
        if ((canvasWidth < 60) || (canvasHeight < 40)) {
            return
        }

        const seriesList = _buildSeries()
        const labelFont  = Math.max(8, Math.round(ScreenTools.defaultFontPixelHeight * 0.7))
        const leftMargin   = Math.round(labelFont * 3.4)
        const rightMargin  = Math.round(labelFont * 0.6)
        const topMargin    = Math.round(labelFont)
        const bottomMargin = Math.round(labelFont * 1.9)
        const plotWidth    = canvasWidth - leftMargin - rightMargin
        const plotHeight   = canvasHeight - topMargin - bottomMargin
        if ((plotWidth < 16) || (plotHeight < 16)) {
            return
        }

        const activeSeries = []
        for (const series of seriesList) {
            if (series.points.length > 0) {
                activeSeries.push(series)
            }
        }

        ctx.font = labelFont + "px sans-serif"
        ctx.textBaseline = "middle"

        if (activeSeries.length === 0) {
            ctx.fillStyle = "rgba(255,255,255,0.7)"
            ctx.textAlign = "center"
            ctx.fillText(qsTr("Waiting for telemetry"), canvasWidth / 2, canvasHeight / 2)
            return
        }

        const firstTime = samples[0].t
        const lastTime  = samples[samples.length - 1].t
        const timeSpan  = Math.max(1, lastTime - firstTime)

        // 单参数模式显示真实数值，全部参数模式显示归一化百分比
        let minY = 0
        let maxY = 1
        if (_singleMode) {
            minY = activeSeries[0].min
            maxY = activeSeries[0].max
            if (!isFinite(minY) || !isFinite(maxY) || ((maxY - minY) < 1e-9)) {
                const center = isFinite(minY) ? minY : 0
                minY = center - 0.5
                maxY = center + 0.5
            }
        }

        // 横向网格 + Y 轴刻度
        const gridSteps = 4
        ctx.lineWidth = 1
        ctx.strokeStyle = "rgba(255,255,255,0.18)"
        ctx.fillStyle = "rgba(255,255,255,0.75)"
        ctx.textAlign = "right"
        for (let i = 0; i <= gridSteps; i++) {
            const y = topMargin + (plotHeight * i) / gridSteps
            ctx.beginPath()
            ctx.moveTo(leftMargin, y)
            ctx.lineTo(leftMargin + plotWidth, y)
            ctx.stroke()

            const text = _singleMode
                       ? _formatValue(maxY - ((maxY - minY) * i) / gridSteps)
                       : Math.round(100 - (100 * i) / gridSteps) + "%"
            ctx.fillText(text, leftMargin - Math.round(labelFont * 0.4), y)
        }

        const xToPixel = (time) => leftMargin + ((time - firstTime) / timeSpan) * plotWidth
        const yToPixel = (value, series) => {
            if (_singleMode) {
                return topMargin + ((maxY - value) / (maxY - minY)) * plotHeight
            }
            const span = series.max - series.min
            const normalized = (span > 1e-9) ? ((value - series.min) / span) : 0.5
            return topMargin + (1 - normalized) * plotHeight
        }

        ctx.save()
        ctx.beginPath()
        ctx.rect(leftMargin, topMargin, plotWidth, plotHeight)
        ctx.clip()

        ctx.lineWidth = Math.max(1, labelFont * 0.16)
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        for (const series of activeSeries) {
            ctx.strokeStyle = series.color
            ctx.beginPath()
            let started = false
            for (const point of series.points) {
                const x = xToPixel(point.x)
                const y = yToPixel(point.y, series)
                if (started) {
                    ctx.lineTo(x, y)
                } else {
                    ctx.moveTo(x, y)
                    started = true
                }
            }
            ctx.stroke()
        }
        ctx.restore()

        // X 轴时间刻度（首 / 末两条，末条右对齐避免出界）
        ctx.fillStyle = "rgba(255,255,255,0.75)"
        ctx.textBaseline = "top"
        ctx.textAlign = "left"
        ctx.fillText(Qt.formatTime(new Date(firstTime), "hh:mm:ss"), leftMargin, topMargin + plotHeight + 3)
        ctx.textAlign = "right"
        ctx.fillText(Qt.formatTime(new Date(lastTime), "hh:mm:ss"), leftMargin + plotWidth, topMargin + plotHeight + 3)
    }
}
