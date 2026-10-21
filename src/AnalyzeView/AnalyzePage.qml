import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

/// Base view control for all Analyze pages
Item {
    anchors.fill:               parent
    anchors.margins:            ScreenTools.defaultFontPixelWidth

    property alias  pageComponent:      pageLoader.sourceComponent
    property alias  pageDescription:    pageDescriptionLabel.text
    property alias  headerComponent:    headerLoader.sourceComponent
    property real   availableWidth:     width  - pageLoader.x
    property real   availableHeight:    height - mainContent.y
    property bool   allowPopout:        false
    property bool   popped:             false
    property real   _margins:           ScreenTools.defaultFontPixelHeight * 0.5

    /// 移动端（安卓遥控器竖横屏）屏幕可用的高字都很紧张：页面描述文字区占掉一大片，
    /// 把内容推到屏幕下方、顶部整段空白。因此手机上直接隐藏标题/描述区，内容顶格。
    readonly property bool _hideHeading: ScreenTools.isMobile || ScreenTools.isShortScreen

    signal popout()

    Loader {
        id:                     headerLoader
        anchors.topMargin:      _margins
        anchors.top:            parent.top
        anchors.left:           parent.left
        anchors.rightMargin:    _margins
        anchors.right:          floatIcon.left
        visible:                !_hideHeading && headerLoader.sourceComponent !== null
    }

    Column {
        id:                     headingColumn
        anchors.topMargin:      _margins
        anchors.top:            parent.top
        anchors.left:           parent.left
        anchors.rightMargin:    _margins
        anchors.right:          floatIcon.visible ? floatIcon.left : parent.right
        spacing:                _margins
        visible:                !_hideHeading && headerLoader.sourceComponent === null
        QGCLabel {
            id:                 pageDescriptionLabel
            anchors.left:       parent.left
            anchors.right:      parent.right
            wrapMode:           Text.WordWrap
        }
    }

    Item {
        id:                     mainContent
        anchors.topMargin:      _hideHeading ? 0 : ScreenTools.defaultFontPixelHeight
        anchors.top:            headerLoader.sourceComponent === null ? (headingColumn.visible ? headingColumn.bottom : parent.top) : headerLoader.bottom
        anchors.bottom:         parent.bottom
        anchors.left:           parent.left
        anchors.right:          parent.right
        clip:                   true
        Loader {
            id:                 pageLoader
        }
    }

    QGCColoredImage {
        id:                     floatIcon
        anchors.verticalCenter: headerLoader.visible ? headerLoader.verticalCenter : headingColumn.verticalCenter
        anchors.right:          parent.right
        width:                  ScreenTools.defaultFontPixelHeight * 2
        height:                 width
        sourceSize.width:       width
        source:                 "/qmlimages/FloatingWindow.svg"
        fillMode:               Image.PreserveAspectFit
        color:                  qgcPal.text
        visible:                allowPopout && !popped && !ScreenTools.isMobile
        QGCMouseArea {
            fillItem:       floatIcon
            onClicked:      popout()
        }
    }
}
