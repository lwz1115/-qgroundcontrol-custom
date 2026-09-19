import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// 水质热力图：X 轴时间、Y 轴参数名、颜色深浅表示数值大小（蓝低 -> 红高）。
/// 数据由 WaterQualityLog::heatmapGrid() 按时间段聚合出来，界面只做颜色映射与绘制。
Item {
    id: control

    /// 数据源（WaterQualityLog）
    property var  log:          null
    /// 聚合用的时间范围（秒）
    property real rangeMin:     0
    property real rangeMax:     1
    /// 横向格数
    property int  columnCount:  120

    /// 悬停提示：参数名、时间、数值
    signal hoverChanged(string rowName, string timeText, string valueText)

    readonly property real _labelWidth: ScreenTools.defaultFontPixelWidth * 8

    property var  _rowNames:  []   ///< 参与显示的参数名
    property var  _grid:      []   ///< 每行每列的平均值（NaN 表示空格）
    property real _minValue:  0
    property real _maxValue:  1

    /// 数值 -> 0..1（用于颜色映射）
    function _normalized(value) {
        if (isNaN(value) || (_maxValue <= _minValue)) {
            return 0
        }
        return Math.max(0, Math.min(1, (value - _minValue) / (_maxValue - _minValue)))
    }

    /// 0..1 -> 颜色：低=蓝，中=绿/黄，高=红
    function colorForNormalized(t) {
        return Qt.hsla(((1 - t) * 240) / 360, 0.85, 0.5, 1)
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

    /// 重新向数据源要一次聚合结果（勾选/时间范围变化时调用）
    function refresh() {
        if (!log || !log.loaded) {
            _rowNames = []
            _grid = []
            canvas.requestPaint()
            return
        }

        _rowNames = log.parameterNames
        _grid = log.heatmapGrid(rangeMin, rangeMax, columnCount)

        // 颜色范围取全体有效值的极值
        let minValue = Number.MAX_VALUE
        let maxValue = -Number.MAX_VALUE
        for (let row = 0; row < _grid.length; row++) {
            for (let column = 0; column < _grid[row].length; column++) {
                const value = _grid[row][column]
                if (isNaN(value)) {
                    continue
                }
                if (value < minValue) minValue = value
                if (value > maxValue) maxValue = value
            }
        }
        if (minValue > maxValue) {
            minValue = 0
            maxValue = 1
        }
        if ((maxValue - minValue) < 1e-9) {
            maxValue = minValue + 1
        }
        _minValue = minValue
        _maxValue = maxValue

        canvas.requestPaint()
    }

    onLogChanged:       refresh()
    onRangeMinChanged:  refresh()
    onRangeMaxChanged:  refresh()
    onColumnCountChanged: refresh()

    RowLayout {
        anchors.fill: parent
        spacing:      ScreenTools.defaultFontPixelWidth * 0.5

        // Y 轴：参数名
        Column {
            Layout.fillHeight:      true
            Layout.preferredWidth:  control._labelWidth
            spacing:                0

            Repeater {
                model: control._rowNames

                QGCLabel {
                    width:          control._labelWidth
                    height:         control._rowNames.length > 0 ? (canvas.height / control._rowNames.length) : 0
                    text:           modelData
                    elide:          Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment:   Text.AlignVCenter
                    font.pointSize:      ScreenTools.smallFontPointSize
                }
            }
        }

        // 热力图本体
        Item {
            id:                 plotArea
            Layout.fillWidth:   true
            Layout.fillHeight:  true

            Canvas {
                id:             canvas
                anchors.fill:   parent

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    if ((control._grid.length === 0) || (control._grid[0].length === 0)) {
                        return
                    }
                    const rows = control._grid.length
                    const columns = control._grid[0].length
                    const cellWidth = width / columns
                    const cellHeight = height / rows

                    for (let row = 0; row < rows; row++) {
                        for (let column = 0; column < columns; column++) {
                            const value = control._grid[row][column]
                            ctx.fillStyle = isNaN(value)
                                ? "transparent"
                                : control.colorForNormalized(control._normalized(value))
                            ctx.fillRect(column * cellWidth, row * cellHeight,
                                         Math.ceil(cellWidth), Math.ceil(cellHeight))
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill:   parent
                hoverEnabled:   true

                function _report(mouseX, mouseY) {
                    if ((control._grid.length === 0) || (control._grid[0].length === 0)) {
                        return
                    }
                    const rows = control._grid.length
                    const columns = control._grid[0].length
                    let column = Math.floor((mouseX / width) * columns)
                    let row = Math.floor((mouseY / height) * rows)
                    column = Math.max(0, Math.min(columns - 1, column))
                    row = Math.max(0, Math.min(rows - 1, row))

                    const value = control._grid[row][column]
                    const span = Math.max(1e-9, control.rangeMax - control.rangeMin)
                    const time = control.rangeMin + ((column + 0.5) / columns) * span
                    control.hoverChanged(control._rowNames[row],
                                         control._timeText(time),
                                         isNaN(value) ? "--" : value.toFixed(3))
                }

                onPositionChanged: (mouse) => _report(mouse.x, mouse.y)
                onEntered:         _report(mouseX, mouseY)
                onExited:          control.hoverChanged("", "", "")
            }
        }
    }

    // X 轴时间刻度
    Item {
        anchors.left:           parent.left
        anchors.leftMargin:     control._labelWidth + ScreenTools.defaultFontPixelWidth * 0.5
        anchors.right:          parent.right
        anchors.bottom:         parent.bottom
        height:                 ScreenTools.defaultFontPixelHeight

        Repeater {
            model: 5

            QGCLabel {
                text:               control._timeText(control.rangeMin + ((control.rangeMax - control.rangeMin) * index / 4))
                font.pointSize:     ScreenTools.smallFontPointSize
                x:                  (parent.width / 4) * index - (index === 0 ? 0 : (index === 4 ? width : width / 2))
            }
        }
    }

    // 颜色图例（蓝=低，红=高）
    RowLayout {
        anchors.right:          parent.right
        anchors.bottom:         parent.bottom
        anchors.bottomMargin:   ScreenTools.defaultFontPixelHeight * 1.2
        spacing:                ScreenTools.defaultFontPixelWidth * 0.5

        QGCLabel {
            text:           qsTr("Low")
            font.pointSize: ScreenTools.smallFontPointSize
        }
        Rectangle {
            Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 8
            Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 0.6
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: control.colorForNormalized(0.0) }
                GradientStop { position: 0.5; color: control.colorForNormalized(0.5) }
                GradientStop { position: 1.0; color: control.colorForNormalized(1.0) }
            }
        }
        QGCLabel {
            text:           qsTr("High")
            font.pointSize: ScreenTools.smallFontPointSize
        }
    }
}
