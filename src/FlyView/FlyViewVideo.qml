import QtQuick
import QtMultimedia

import QGroundControl
import QGroundControl.Controls

Item {
    id: _root

    property Item pipView
    property Item pipState: videoPipState

    // ---- 双摄像头主辅状态 ----
    // 主画面（摄像头1）是否有源：由主视频源枚举决定（RTSP/UDP/TCP/… 或 UVC）
    readonly property bool _cam1StreamActive: QGroundControl.videoManager.isStreamSource
                                               || QGroundControl.videoManager.isUvc
    // 摄像头2 是否配置了 RTSP 地址（留空 = 不使用）
    // 摄像头2 是否启用：视频二来源不是 Disabled（来源下拉本身就是开关）
    readonly property bool _cam2Configured:   QGroundControl.settingsManager.videoSettings.videoSource2.rawValue
                                              !== QGroundControl.settingsManager.videoSettings.disabledVideoSource
    // 手动主辅切换（按钮翻转）：false = 摄像头1 主，true = 摄像头2 主。仅双配置时生效。
    property bool _cam2IsMainManual: false
    // 生效的主辅：只填了摄像头2（主源未启用）时它自动为主；双配置时跟随手动开关。
    readonly property bool _cam2IsMain: _cam2Configured && (!_cam1StreamActive || _cam2IsMainManual)
    // 辅画面小窗尺寸：主画面铺满，辅画面叠在右下角；按主画面比例，窗口放大时同比放大
    readonly property real _pipSubWidth:   _root.width * 0.35
    readonly property real _pipSubHeight:  _pipSubWidth * 0.5625
    readonly property real _pipMargin:     ScreenTools.defaultFontPixelHeight * 0.5
    // 切换按钮可见条件：小窗太小会遮挡画面 → 隐藏；全屏，或主画面放大到约 100 字宽以上才显示。
    readonly property bool _showSwitch: {
        if (_root.pipState.state === _root.pipState.fullState) {
            return true
        }
        const mainWidth = _root._cam2IsMain ? cam2View.width : videoStreaming.width
        return mainWidth >= (ScreenTools.defaultFontPixelWidth * 100)
    }

    PipState {
        id:         videoPipState
        pipView:    _root.pipView
        isDark:     true

        onWindowAboutToOpen: {
            QGroundControl.videoManager.stopVideo()
            videoStartDelay.start()
        }

        onWindowAboutToClose: {
            QGroundControl.videoManager.stopVideo()
            videoStartDelay.start()
        }

        onStateChanged: {
            if (pipState.state !== pipState.fullState) {
                QGroundControl.videoManager.fullScreen = false
            }
        }
    }

    Timer {
        id:           videoStartDelay
        interval:     2000;
        running:      false
        repeat:       false
        onTriggered:  QGroundControl.videoManager.startVideo()
    }

    //-- Video Streaming（摄像头1 渲染区）：主时铺满，辅时缩到右下小窗
    FlightDisplayViewVideo {
        id:             videoStreaming
        x:              _root._cam2IsMain ? _root.width - width - _root._pipMargin : 0
        y:              _root._cam2IsMain ? _root.height - height - _root._pipMargin : 0
        width:          _root._cam2IsMain ? _root._pipSubWidth : _root.width
        height:         _root._cam2IsMain ? _root._pipSubHeight : _root.height
        z:              _root._cam2IsMain ? 10 : 0
        useSmallFont:   _root.pipState.state !== _root.pipState.fullState
        visible:        QGroundControl.videoManager.isStreamSource || QGroundControl.videoManager.isUvc
    }

    //-- 摄像头2 渲染区：配置了 rtspUrl2 才显示；主时铺满，辅时缩到右下小窗
    Rectangle {
        id:             cam2View
        visible:        _root._cam2Configured
        x:              _root._cam2IsMain ? 0 : _root.width - width - _root._pipMargin
        y:              _root._cam2IsMain ? 0 : _root.height - height - _root._pipMargin
        width:          _root._cam2IsMain ? _root.width : _root._pipSubWidth
        height:         _root._cam2IsMain ? _root.height : _root._pipSubHeight
        z:              _root._cam2IsMain ? 0 : 10
        color:          "black"
        border.color:   Qt.rgba(1, 1, 1, _root._cam2IsMain ? 0 : 0.45)
        border.width:   1

        VideoOutput {
            objectName: "videoContent2"
            anchors.fill: parent
            fillMode:       VideoOutput.PreserveAspectFit
        }

        // 摄像头2 角标（辅画面时显示）
        QGCLabel {
            text:            qsTr("Camera 2")
            color:           "white"
            font.pointSize:  ScreenTools.smallFontPointSize
            anchors.top:     parent.top
            anchors.left:    parent.left
            anchors.margins: ScreenTools.defaultFontPixelHeight * 0.3
            visible:         !_root._cam2IsMain
        }
    }

    //-- 切换按钮：贴在当前辅画面左上角；仅两路都启用时可切（Q2=D）
    QGCButton {
        id:              camSwitchButton
        text:            "⇌"
        z:               20
        width:           ScreenTools.defaultFontPixelHeight * 1.5
        height:          width
        visible:         _root._showSwitch && _root._cam1StreamActive && _root._cam2Configured
        anchors.top:       (_root._cam2IsMain ? videoStreaming : cam2View).top
        anchors.left:      (_root._cam2IsMain ? videoStreaming : cam2View).left
        anchors.topMargin:  ScreenTools.defaultFontPixelHeight * 1.6 // 让开左上角“Camera 2”角标
        anchors.leftMargin: _root._pipMargin
        onClicked:          _root._cam2IsMainManual = !_root._cam2IsMainManual
    }

    QGCLabel {
        text: qsTr("Double-click to exit full screen")
        font.pointSize: ScreenTools.largeFontPointSize
        visible: QGroundControl.videoManager.fullScreen
        anchors.centerIn: parent

        onVisibleChanged: {
            if (visible) {
                labelAnimation.start()
            }
        }

        PropertyAnimation on opacity {
            id: labelAnimation
            duration: 10000
            from: 1.0
            to: 0.0
            easing.type: Easing.InExpo
        }
    }

    OnScreenGimbalController {
        id:                      onScreenGimbalController
        anchors.fill:            parent
        cameraTrackingEnabled:   !!(videoStreaming._camera && videoStreaming._camera.trackingEnabled)
    }

    OnScreenCameraTrackingController {
        id:                      cameraTrackingController
        anchors.fill:            parent
        camera:                  videoStreaming._camera
        videoWidth:              videoStreaming.getWidth()
        videoHeight:             videoStreaming.getHeight()
    }

    MouseArea {
        id:                         flyViewVideoMouseArea
        anchors.fill:               parent
        enabled:                    pipState.state === pipState.fullState

        property real _pressX:      0
        property real _pressY:      0
        property bool _dragging:    false
        property bool _doubleClicked: false
        readonly property real _dragThreshold: 10

        // Defer single-click handling so a double-click (fullscreen toggle) doesn't also
        // fire an unintended gimbal click-to-point/tracking command on its first click.
        Timer {
            id:         singleClickTimer
            interval:   Qt.styleHints.mouseDoubleClickInterval
            repeat:     false

            property real clickX: 0
            property real clickY: 0

            onTriggered: {
                onScreenGimbalController.mouseClicked(clickX, clickY)
                cameraTrackingController.mouseClicked(clickX, clickY)
            }
        }

        onDoubleClicked: {
            // Fires on the second press of a double-click. The second release still emits
            // onReleased, so flag it to prevent re-arming the single-click timer.
            _doubleClicked = true
            singleClickTimer.stop()
            QGroundControl.videoManager.fullScreen = !QGroundControl.videoManager.fullScreen
        }

        onPressed: (mouse) => {
            _pressX = mouse.x
            _pressY = mouse.y
            _dragging = false
            // Clear any stale flag (e.g. double-click followed by drag releases through the
            // drag branch without consuming it). Safe: pressed is emitted before doubleClicked.
            _doubleClicked = false
        }

        onPositionChanged: (mouse) => {
            if (!_dragging && (Math.abs(mouse.x - _pressX) >= _dragThreshold || Math.abs(mouse.y - _pressY) >= _dragThreshold)) {
                _dragging = true
                onScreenGimbalController.mouseDragStart(_pressX, _pressY)
                cameraTrackingController.mouseDragStart(_pressX, _pressY)
            }
            if (_dragging) {
                onScreenGimbalController.mouseDragPositionChanged(mouse.x, mouse.y)
                cameraTrackingController.mouseDragPositionChanged(mouse.x, mouse.y)
            }
        }

        onReleased: (mouse) => {
            if (_dragging) {
                onScreenGimbalController.mouseDragEnd()
                cameraTrackingController.mouseDragEnd(mouse.x, mouse.y)
            } else if (_doubleClicked) {
                // Second release of a double-click - fullscreen toggle already handled
                _doubleClicked = false
            } else {
                singleClickTimer.clickX = mouse.x
                singleClickTimer.clickY = mouse.y
                singleClickTimer.restart()
            }
            _dragging = false
        }
    }

    ProximityRadarVideoView{
        anchors.fill:   parent
        vehicle:        QGroundControl.multiVehicleManager.activeVehicle
    }

    ObstacleDistanceOverlayVideo {
        id: obstacleDistance
        showText: pipState.state === pipState.fullState
    }
}
