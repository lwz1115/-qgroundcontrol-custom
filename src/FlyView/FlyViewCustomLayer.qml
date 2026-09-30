import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QtLocation
import QtPositioning
import QtQuick.Window
import QtQml.Models

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView
import QGroundControl.FlightMap

// To implement a custom overlay copy this code to your own control in your custom code source. Then override the
// FlyViewCustomLayer.qml resource with your own qml. See the custom example and documentation for details.
Item {
    id: _root

    property var parentToolInsets               // These insets tell you what screen real estate is available for positioning the controls in your overlay
    property var totalToolInsets:   _toolInsets // These are the insets for your custom overlay additions
    property var mapControl
    /// 摄像头小窗（FlyView.qml 的 PipView）。水质与采样卡片一竖排、紧贴在它顶部上方，随它缩放/移动。
    property var pipView

    /// PipView 挂在 FlyView 根上，而本层铺在 widgetLayer（原点被工具条下移了 topMargin）。
    /// 直接用 PipView 的坐标会把图标下移一整个工具条高度、正好落进小窗里被它盖住 —— 必须换算到本层坐标。
    readonly property point pipTopLeft: {
        // mapToItem 自身不建立响应式依赖：显式读一遍小窗几何，小窗缩放时本绑定才会重算
        const gx = pipView ? pipView.x : 0
        const gy = pipView ? pipView.y : 0
        const gw = pipView ? pipView.width : 0
        const gh = pipView ? pipView.height : 0
        return pipView ? pipView.mapToItem(_root, 0, 0) : Qt.point(0, 0)
    }
    readonly property real pipWidth: pipView ? pipView.width : 0

    // since this file is a placeholder for the custom layer in a standard build, we will just pass through the parent insets
    QGCToolInsets {
        id:                     _toolInsets
        // 全部原样透传。水质图标是浮层，靠自身的 _leftInset / _bottomInset 避让画中画即可，
        // 绝不能再往 insets 上加增量 —— 这个值同时被 FlyViewWidgetLayer 用来算画中画和虚拟
        // 摇杆的避让余量，加一点就会把画中画顶出左下角。
        leftEdgeTopInset:       parentToolInsets.leftEdgeTopInset
        leftEdgeCenterInset:    parentToolInsets.leftEdgeCenterInset
        leftEdgeBottomInset:    parentToolInsets.leftEdgeBottomInset
        rightEdgeTopInset:      parentToolInsets.rightEdgeTopInset
        rightEdgeCenterInset:   parentToolInsets.rightEdgeCenterInset
        rightEdgeBottomInset:   parentToolInsets.rightEdgeBottomInset
        topEdgeLeftInset:       parentToolInsets.topEdgeLeftInset
        topEdgeCenterInset:     parentToolInsets.topEdgeCenterInset
        topEdgeRightInset:      parentToolInsets.topEdgeRightInset
        bottomEdgeLeftInset:    parentToolInsets.bottomEdgeLeftInset
        bottomEdgeCenterInset:  parentToolInsets.bottomEdgeCenterInset
        bottomEdgeRightInset:   parentToolInsets.bottomEdgeRightInset
    }

    // 无人船水质监测：左下角水滴图标 + 实时折线图（卡片一竖排，紧贴摄像头小窗顶部）
    WaterQualityOverlay {
        id:                 waterQualityOverlay
        anchors.fill:       parent
        parentToolInsets:   _root.parentToolInsets
        pipTopLeft:         _root.pipTopLeft
        pipWidth:           _root.pipWidth
    }

    // 水质采样控制：与水滴卡片同一竖列、排在它上方，一起紧贴摄像头小窗顶部
    WaterSamplingControl {
        id:                 waterSamplingControl
        anchors.fill:       parent
        parentToolInsets:   _root.parentToolInsets
        pipTopLeft:         _root.pipTopLeft
        pipWidth:           _root.pipWidth
    }
}
