pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtLocation
import QtPositioning

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlightMap

import "WaterQualityUtils.js" as WQUtils

/// 水质地图热力路径。
///
/// 把导入数据里的经纬度按时间顺序连成任务路径，每一段按所选参数在该段的数值着色
/// （蓝低 -> 红高），颜色不同的段拼起来就是一条彩色路径。
/// QtLocation 的 MapPolyline 不支持渐变，所以按段拆成多条两点折线；
/// 段数由 WaterQualityLog::geoPathForParameter() 的 maxPoints 限制，避免拖慢地图渲染。
Item {
    id: control

    /// 数据源（WaterQualityLog）
    property var    log:           null
    /// 参与着色的参数名（内部规范名，用于向数据源取值，不参与翻译）
    property string parameterName: ""
    /// 图例上显示的参数名（页面传进来的本地化显示名；为空时退回规范名）
    property string parameterLabel: ""
    /// 时间筛选范围（秒）
    property real   rangeMin:      0
    property real   rangeMax:      1
    /// 最多拆成多少段（+1 个点）
    property int    maxSegments:   200

    readonly property real _lineWidth:  ScreenTools.defaultFontPixelHeight * 0.4
    /// 数值缺失的段用灰色，区别于热力色（否则看起来像数值最低）
    readonly property color _noDataColor: Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.35)

    property var  _segments: []
    property var  _bounds:   null
    property real _minValue: 0
    property real _maxValue: 1
    readonly property bool _hasPath: _segments.length > 0

    /// 重新向数据源要一次路径（导入数据 / 切换参数 / 改时间范围时调用）
    function refresh() {
        _segments = []
        _bounds   = null
        _minValue = 0
        _maxValue = 1

        if (!log || !log.loaded || (parameterName === "")) {
            return
        }

        const points = log.geoPathForParameter(parameterName, rangeMin, rangeMax, maxSegments + 1)
        if (points.length < 2) {
            return
        }

        let minValue = Number.MAX_VALUE
        let maxValue = -Number.MAX_VALUE
        let minLat = points[0].latitude
        let maxLat = minLat
        let minLon = points[0].longitude
        let maxLon = minLon

        for (let i = 0; i < points.length; i++) {
            const point = points[i]
            if (!isNaN(point.value)) {
                if (point.value < minValue) minValue = point.value
                if (point.value > maxValue) maxValue = point.value
            }
            if (point.latitude  < minLat) minLat = point.latitude
            if (point.latitude  > maxLat) maxLat = point.latitude
            if (point.longitude < minLon) minLon = point.longitude
            if (point.longitude > maxLon) maxLon = point.longitude
        }

        const hasValue = (minValue <= maxValue)
        const segments = []
        for (let i = 1; i < points.length; i++) {
            const from = points[i - 1]
            const to   = points[i]
            // 一段的数值取两端平均；只有一端有值时用有值的那端
            let value = NaN
            if (!isNaN(from.value) && !isNaN(to.value)) {
                value = (from.value + to.value) / 2
            } else if (!isNaN(from.value)) {
                value = from.value
            } else if (!isNaN(to.value)) {
                value = to.value
            }

            let color = _noDataColor
            if (!isNaN(value) && hasValue) {
                color = WQUtils.colorForNormalized((maxValue > minValue) ? (value - minValue) / (maxValue - minValue)
                                                                         : 0.5)
            }

            segments.push({
                path: [QtPositioning.coordinate(from.latitude, from.longitude),
                       QtPositioning.coordinate(to.latitude, to.longitude)],
                color: color
            })
        }

        _minValue = hasValue ? minValue : 0
        _maxValue = hasValue ? maxValue : 1
        _bounds   = { minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon }
        _segments = segments

        // 地图可能还没完成初始化，等这一轮布局结束再定位
        Qt.callLater(_fitPath)
    }

    /// 把视野拉到整条路径上
    function _fitPath() {
        if (!_bounds) {
            return
        }
        // 路径只有一点（或所有点重合）时 setVisibleRegion 会退化成最小范围，给一点余量
        const padding = 1e-5
        const minLat = _bounds.minLat - padding
        const maxLat = _bounds.maxLat + padding
        const minLon = _bounds.minLon - padding
        const maxLon = _bounds.maxLon + padding
        geoMap.setVisibleRegion(QtPositioning.rectangle(QtPositioning.coordinate(maxLat, minLon),
                                                       QtPositioning.coordinate(minLat, maxLon)))
    }

    FlightMap {
        id:                     geoMap
        anchors.fill:           parent
        mapName:                "WaterQualityMapPath"
        allowGCSLocationCenter: true

        // 每一段一条折线，颜色按该段的数值取自热力色带。
        // 模型驱动的地图元素必须用 MapItemView（它自己会把 delegate 注册进 Map），
        // 直接放在 Repeater 里依赖 Repeater 重设 parent 的行为不可靠。
        MapItemView {
            model: control._segments

            delegate: MapPolyline {
                required property var modelData

                line.width: control._lineWidth
                line.color: modelData ? modelData.color : "transparent"
                path:       modelData ? modelData.path : []
            }
        }

        MapScale {
            anchors.margins: ScreenTools.defaultFontPixelWidth
            anchors.left:    parent.left
            anchors.bottom:  parent.bottom
            mapControl:      geoMap
        }
    }

    // 色带：说明颜色对应的数值范围
    Rectangle {
        anchors.margins: ScreenTools.defaultFontPixelWidth
        anchors.right:   parent.right
        anchors.top:     parent.top
        visible:         control._hasPath
        color:           Qt.rgba(0, 0, 0, 0.55)
        border.color:    Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.4)
        border.width:    1
        radius:          ScreenTools.defaultBorderRadius
        width:           legendLayout.implicitWidth + ScreenTools.defaultFontPixelWidth
        height:          legendLayout.implicitHeight + ScreenTools.defaultFontPixelHeight * 0.4

        ColumnLayout {
            id:              legendLayout
            anchors.centerIn: parent
            spacing:         ScreenTools.defaultFontPixelHeight * 0.2

            QGCLabel {
                // 用本地化显示名；图例底色是深色，文字固定用白色保证对比度
                text:      (control.parameterLabel !== "") ? control.parameterLabel : control.parameterName
                color:     "white"
                font.bold: true
            }

            RowLayout {
                spacing: ScreenTools.defaultFontPixelWidth * 0.5

                QGCLabel {
                    text:  control._minValue.toFixed(2)
                    color: "white"
                }

                Rectangle {
                    Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 10
                    Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 0.4

                    // Gradient 是纯数据对象，里面放不了 Repeater，色带停靠点只能写死
                    gradient: Gradient {
                        orientation: Gradient.Horizontal

                        GradientStop { position: 0.00; color: WQUtils.colorForNormalized(0.00) }
                        GradientStop { position: 0.25; color: WQUtils.colorForNormalized(0.25) }
                        GradientStop { position: 0.50; color: WQUtils.colorForNormalized(0.50) }
                        GradientStop { position: 0.75; color: WQUtils.colorForNormalized(0.75) }
                        GradientStop { position: 1.00; color: WQUtils.colorForNormalized(1.00) }
                    }
                }

                QGCLabel {
                    text:  control._maxValue.toFixed(2)
                    color: "white"
                }
            }
        }
    }

    QGCLabel {
        anchors.centerIn: parent
        visible:          !control._hasPath
        font.italic:      true
        text: {
            if (!control.log || !control.log.loaded) {
                return qsTr("Import a file to view the monitoring path")
            }
            if (!control.log.hasGeoData) {
                return qsTr("No longitude/latitude columns in this file")
            }
            return qsTr("Not enough positioned samples in this time range")
        }
    }

    // 切回地图页时地图尺寸才确定，这时再定位一次
    onVisibleChanged: {
        if (visible) {
            Qt.callLater(_fitPath)
        }
    }
}
