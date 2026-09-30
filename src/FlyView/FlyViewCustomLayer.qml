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
        pipView:            _root.pipView
    }

    // 水质采样控制：与水滴卡片同一竖列、排在它上方，一起紧贴摄像头小窗顶部
    WaterSamplingControl {
        id:                 waterSamplingControl
        anchors.fill:       parent
        parentToolInsets:   _root.parentToolInsets
        pipView:            _root.pipView
    }
}
