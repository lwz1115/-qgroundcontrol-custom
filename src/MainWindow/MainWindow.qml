import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FactControls
import QGroundControl.FlyView
import QGroundControl.FlightMap
import QGroundControl.PlanView
import QGroundControl.Toolbar

/// @brief 原生 QML 顶层窗口
/// 这里定义的所有属性对所有 QML 页面可见。
///
/// 本文件是 QGC 界面最顶层的"骨架"（ApplicationWindow 窗口），承担了：
///   1. 主视图的容纳与切换：FlyView（飞行）、PlanView（任务规划）、
///      geoTestView（地理调试，仅调试版）；
///   2. 工具抽屉（toolDrawer）：承载"分析工具 / 飞控配置 / 应用设置"等二级页面；
///   3. 全局作用域变量（globals）与全局函数（视图切换、消息弹窗、关闭检查等），
///      供所有 QML 子页面通过 mainWindow.xxx 调用；
///   4. 各类弹窗：应用消息、飞行器关键警告（criticalVehicleMessagePopup）、
///      指示抽屉（indicatorDrawer）等。
/// 注意：C++ 端通过 QGCApplication 调用这里的函数（如 _showMessageDialog、
/// showCriticalVehicleMessage），实现 C++ ↔ QML 的联动。
ApplicationWindow {
    id:         mainWindow
    visible:    true
    // 对 Android 的特殊处理，可防止较新 Android 版本在屏幕边缘出现白条
    flags:      Qt.Window | (ScreenTools.isAndroid ? Qt.ExpandedClientAreaHint | Qt.NoTitleBarBackgroundHint : 0)

    // Qt 6.9+ 会在移动端自动将 ApplicationWindow 的内边距设置为屏幕安全区域插边，
    // 这会让我们的全幅内容产生内缩，并在屏幕边缘留下空白条。
    // QGC 采用边到边绘制并自行管理插边，因此将内边距清零。
    topPadding:    0
    bottomPadding: 0
    leftPadding:   0
    rightPadding:  0

    Component.onCompleted: {
        // 开始首次运行提示的序列
        firstRunPromptManager.nextPrompt()
    }

    /// 保存主窗口的位置和大小，并在下次以相同的位置和大小重新打开
    MainWindowSavedState {
        window: mainWindow
    }

    // 首次运行提示管理器：按顺序依次弹出多个"首次使用引导"对话框
    // （例如隐私说明、使用引导），全部显示完后调用 showPreFlightChecklistIfNeeded()。
    // 注意：组件卸载时必须调用 clearNextPromptSignal() 断开信号，
    // 否则对话框关闭信号会指向已销毁的对象（QML 端 Qt 不会自动断开）。
    QtObject {
        id: firstRunPromptManager

        property var currentDialog:     null        // 当前正在显示的引导对话框
        property var rgPromptIds:       QGroundControl.corePlugin.firstRunPromptsToShow()  // 需要依次展示的引导列表
        property int nextPromptIdIndex: 0          // 下一个要展示的引导下标

        // 断开"对话框关闭"信号与 nextPrompt 的连接，防止对象销毁后仍被回调
        function clearNextPromptSignal() {
            if (currentDialog) {
                currentDialog.closed.disconnect(nextPrompt)
            }
        }

        // 弹出下一个引导；若已全部弹完，则进入正常主界面（触发起飞前检查清单）
        function nextPrompt() {
            if (nextPromptIdIndex < rgPromptIds.length) {
                var component = Qt.createComponent(QGroundControl.corePlugin.firstRunPromptResource(rgPromptIds[nextPromptIdIndex]));
                currentDialog = component.createObject(mainWindow)
                currentDialog.closed.connect(nextPrompt)   // 关闭当前引导后自动弹下一个
                currentDialog.open()
                nextPromptIdIndex++
            } else {
                currentDialog = null
                showPreFlightChecklistIfNeeded()
            }
        }
    }

    readonly property real      _topBottomMargins:          ScreenTools.defaultFontPixelHeight * 0.5

    //-------------------------------------------------------------------------
    //-- 全局作用域变量
    // 把各个 QML 页面都常用的引用集中放在这里，其它页面通过
    // mainWindow.globals.xxx 访问（比到处重复写 QGroundControl.xxx 更简洁）。

    QtObject {
        id: globals

        // 当前活动飞行器（多机时只有一个"活动"机；没有连接时为 null）
        readonly property var       activeVehicle:                  QGroundControl.multiVehicleManager.activeVehicle
        // 界面默认字体的一行高 / 一个字宽（用于按像素精确排版）
        readonly property real      defaultTextHeight:              ScreenTools.defaultFontPixelHeight
        readonly property real      defaultTextWidth:               ScreenTools.defaultFontPixelWidth
        // 飞行视图里的任务规划控制器 / 引导控制器（供其它页面复用）
        readonly property var       planMasterControllerFlyView:    flyView.planController
        readonly property var       guidedControllerFlyView:        flyView.guidedController
        // QGC 启动时刻，用于显示地面站已使用时长
        readonly property var       appStartTime:                   new Date()

        // 存在校验错误的 QGCTextField 数量。用于防止关闭带有校验错误的面板。
        // 当 >0 时，切换视图/关闭窗口都会被阻止（见 allowViewSwitch）。
        property int                validationErrorCount:           0

        // 设置为非空字符串以使用自定义原因阻止导航（例如校准过程中）
        // （比 validationErrorCount 更"强制"：无论有没有校验错误都会阻止）
        property string             navigationBlockedReason:        ""

        // 用于管理 RemoteID 快速访问设置页面的属性
        // （记录用户是否从 RemoteID 指示图标进入，用于决定返回时跳转到哪个设置页）
        property bool               commingFromRIDIndicator:        false
    }

    /// 整个 UI 使用的默认调色板
    /// （集中定义各控件配色，实现白天/夜间主题切换）
    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    //-------------------------------------------------------------------------
    //-- 动作（信号）
    // 由界面控件（如工具栏按钮）发起的"请求"信号。C++ 端或上层 QML 监听这些
    // 信号后执行对应动作：解锁/上锁、VTOL 模式切换、显示起飞前检查清单等。
    // （QML 信号用 signal 关键字声明，可像普通信号一样 connect/onXxx 处理）

    signal armVehicleRequest
    signal forceArmVehicleRequest
    signal disarmVehicleRequest
    signal vtolTransitionToFwdFlightRequest
    signal vtolTransitionToMRFlightRequest
    signal showPreFlightChecklistIfNeeded

    //-------------------------------------------------------------------------
    //-- 全局作用域函数

    // 视图切换前的"放行检查"：若有校验错误或被强制阻止导航，则拒绝切换视图。
    //   参数 previousValidationErrorCount：切换前的错误数（用于判断是否出现新错误）
    //   参数 showErrorOnDisallow：被阻止时是否弹提示气泡
    //   返回值：true=允许切换，false=阻止切换。
    // 调用示例：if (mainWindow.allowViewSwitch()) { ... } 先检查再切换。
    function allowViewSwitch(previousValidationErrorCount = 0, showErrorOnDisallow = true) {
        // 检查是否存在明确的导航阻止（例如校准进行中）
        if (globals.navigationBlockedReason !== "") {
            if (showErrorOnDisallow) {
                validationErrorToast.text = globals.navigationBlockedReason
                if (validationErrorToast.visible) {
                    validationErrorToast.close()
                }
                validationErrorToast.open()
            }
            return false
        }
        // 对当前焦点控件运行校验，确保在切换视图前其值是有效的
        // （触发 FactTextField 的"编辑完成"，即时校验并同步值）
        if (mainWindow.activeFocusControl instanceof FactTextField) {
            mainWindow.activeFocusControl._onEditingFinished()
        }
        var allowed = globals.validationErrorCount <= previousValidationErrorCount
        if (!allowed && showErrorOnDisallow) {
            validationErrorToast.text = qsTr("Please correct the invalid value before continuing")
            if (validationErrorToast.visible) {
                validationErrorToast.close()
            }
            validationErrorToast.open()
        }
        return allowed
    }

    // 切换到"任务规划"视图：隐藏其它视图，只显示 PlanView
    function showPlanView() {
        flyView.visible = false
        planView.visible = true
        geoTestView.visible = false
        toolDrawer.visible = false
    }

    // 切换到"飞行"视图：显示 FlyView（主飞行界面，默认首页）
    function showFlyView() {
        flyView.visible = true
        planView.visible = false
        geoTestView.visible = false
        toolDrawer.visible = false
    }

    // 切换到"地理调试"视图（仅调试构建可用，用于地图功能开发测试）
    function showGeoTestView() {
        if (!ScreenTools.isDebug) {
            return
        }
        flyView.visible = false
        planView.visible = false
        geoTestView.visible = true
        toolDrawer.visible = false
    }

    // 打开"工具抽屉"：在抽屉里加载指定的二级工具页面。
    //   参数 toolTitle：标题文字；toolSource：要加载的 QML 文件地址；
    //   toolIcon：抽屉顶部返回键图标（按当前视图自动切换纸飞机/规划图标）。
    function showTool(toolTitle, toolSource, toolIcon) {
        toolDrawer.backIcon     = flyView.visible ? "/qmlimages/PaperPlane.svg" : "/qmlimages/Plan.svg"
        toolDrawer.toolTitle    = toolTitle
        toolDrawer.toolSource   = toolSource
        toolDrawer.toolIcon     = toolIcon
        toolDrawer.visible      = true
    }

    // 快捷入口①：打开"分析工具"页面（日志、MAVLink 控制台、参数等）
    function showAnalyzeTool() {
        showTool(qsTr("Analyze Tools"), "qrc:/qml/QGroundControl/AnalyzeView/AnalyzeView.qml", "/qmlimages/Analyze.svg")
    }

    // 快捷入口②：打开"飞控配置"页面（机架、校准、参数等）
    function showVehicleConfig() {
        showTool(qsTr("Vehicle Configuration"), "qrc:/qml/QGroundControl/VehicleSetup/VehicleConfigView.qml", "/qmlimages/Gears.svg")
    }

    // 打开"飞控配置"并直接定位到"参数"面板
    function showVehicleConfigParametersPage() {
        showVehicleConfig()
        toolDrawerLoader.item.showParametersPanel()
    }

    // 打开"飞控配置"并直接定位到指定组件（如电池/电源等已知组件）的配置面板
    function showKnownVehicleComponentConfigPage(knownVehicleComponent) {
        showVehicleConfig()
        let vehicleComponent = globals.activeVehicle.autopilotPlugin.findKnownVehicleComponent(knownVehicleComponent)
        if (vehicleComponent) {
            toolDrawerLoader.item.showVehicleComponentPanel(vehicleComponent)
        }
    }

    // 快捷入口③：打开"应用设置"页面；可传入具体设置页名直接定位
    function showSettingsTool(settingsPage = "") {
        showTool(qsTr("Application Settings"), "qrc:/qml/QGroundControl/Controls/AppSettings.qml", "/res/QGCLogoWhite")
        if (settingsPage !== "") {
            toolDrawerLoader.item.showSettingsPage(settingsPage)
        }
    }

    //-------------------------------------------------------------------------
    //-- 全局简单消息对话框
    // 统一的"简单消息弹窗"底层实现：动态创建一个 QGCSimpleMessageDialog。
    // 其它 _showXxxDialog 最终都汇聚到这里，避免重复代码。
    //   参数 buttons：要显示的按钮（Dialog.Ok / Dialog.Yes|No 等）；
    //   acceptFunction / closeFunction：点确定 / 关闭时执行的回调；
    //   bypassNavigationCheck：是否绕过视图切换检查（关闭类弹窗通常需要）。
    function _showMessageDialogWorker(owner, dialogTitle, dialogText, buttons = Dialog.Ok, acceptFunction = null, closeFunction = null, bypassNavigationCheck = false) {
        let dialog = simpleMessageDialogComponent.createObject(owner, { title: dialogTitle, text: dialogText, buttons: buttons, acceptFunction: acceptFunction, closeFunction: closeFunction, bypassNavigationCheck: bypassNavigationCheck })
        dialog.open()
    }

    // 此变体仅供 QGCApplication 调用
    function _showMessageDialog(dialogTitle, dialogText) {
        _showMessageDialogWorker(mainWindow, dialogTitle, dialogText)
    }

    // 此变体仅供 QGCApplication 调用。确定将重启当前活动飞行器。
    function _showRebootVehicleDialog(dialogTitle, dialogText) {
        _showMessageDialogWorker(mainWindow, dialogTitle,
                                 dialogText + " " + qsTr("Click Ok to reboot the vehicle now."),
                                 Dialog.Ok | Dialog.Cancel,
                                 function() {
                                     const activeVehicle = QGroundControl.multiVehicleManager.activeVehicle
                                     if (activeVehicle) {
                                         activeVehicle.rebootVehicle()
                                     }
                                 })
    }

    Connections {
        target: QGroundControl

        function onShowMessageDialogRequested(owner, title, text, buttons, acceptFunction, closeFunction) {
            _showMessageDialogWorker(owner, title, text, buttons, acceptFunction, closeFunction)
        }
    }

    Component {
        id: simpleMessageDialogComponent

        QGCSimpleMessageDialog {
        }
    }

    property bool _forceClose: false
    property bool suppressCriticalVehicleMessages: false

    // 执行"真正的关闭"：设置 _forceClose 标记（跳过关闭前的各种检查），
    // 断开引导对话框的信号、关闭通信链路、停止视频，最后关闭主窗口。
    // 只有所有关闭前检查（performCloseChecks）都通过后才会走到这里。
    function finishCloseProcess() {
        _forceClose = true
        // 出于某种原因，在 QML 端 Qt 不会在对象销毁时自动断开信号。
        // 因此我们必须自行处理，否则在应用关闭时信号会流向一个已不存在的对象。
        firstRunPromptManager.clearNextPromptSignal()
        QGroundControl.linkManager.shutdown()
        QGroundControl.videoManager.stopVideo();
        mainWindow.close()
    }

    // 关闭前检查的总入口：依次检查 ①未保存任务 ②待写参数 ③活动连接，
    // 每项都可通过 _closeChecksToSkip 位掩码单独跳过（见下面的 *Mask 常量）。
    // 全部通过才调用 finishCloseProcess() 真正关闭；否则返回 false 取消关闭。
    // 返回 true 表示允许关闭。
    readonly property int _skipUnsavedMissionCheckMask: 0x01            // 跳过"未保存任务"检查
    readonly property int _skipPendingParameterWritesCheckMask: 0x02    // 跳过"待写参数"检查
    readonly property int _skipActiveConnectionsCheckMask: 0x04         // 跳过"活动连接"检查
    property int _closeChecksToSkip: 0
    property bool _reentrantCloseGuard: false   // 防止弹窗回调里重复进入关闭流程
    function performCloseChecks() {
        if (!(_closeChecksToSkip & _skipUnsavedMissionCheckMask) && !checkForUnsavedMission()) {
            return false
        }
        if (!(_closeChecksToSkip & _skipPendingParameterWritesCheckMask) && !checkForPendingParameterWrites()) {
            return false
        }
        if (!(_closeChecksToSkip & _skipActiveConnectionsCheckMask) && !checkForActiveConnections()) {
            return false
        }
        finishCloseProcess()
        return true
    }

    // 检查①：是否有未保存/未上传的任务编辑？
    // 有则弹出确认框；用户点"是"后把该项标记为已跳过并重新执行关闭流程。
    function checkForUnsavedMission() {
        // 仅当编辑既未保存到磁盘也未上传到飞行器时才发出警告。
        // 如果两者中任一项已发生，编辑是可恢复的，因此关闭不会丢失任何内容。
        // 没有活动飞行器时不可能发生过上传，因此无论 dirtyForUpload 如何，
        // 都将任务视为未上传。
        if (planView._planMasterController.dirtyForSave &&
                (planView._planMasterController.dirtyForUpload || !QGroundControl.multiVehicleManager.activeVehicle)) {
            let accepted = false
            _reentrantCloseGuard = true
            _showMessageDialogWorker(mainWindow, qsTr("Unsaved Mission"),
                              qsTr("You have a mission edit in progress which has not been saved/uploaded. If you close you will lose changes. Are you sure you want to close?"),
                              Dialog.Yes | Dialog.No,
                              function() { accepted = true; _closeChecksToSkip |= _skipUnsavedMissionCheckMask; performCloseChecks() },
                              function() { if (!accepted) _reentrantCloseGuard = false },
                              true /* 绕过导航检查 */)
            return false
        } else {
            return true
        }
    }

    // 检查②：是否有尚未写入飞行器的参数修改（pendingWrites）？
    // 遍历所有连接的飞行器，若发现有待写参数则弹出确认框。
    function checkForPendingParameterWrites() {
        for (var index=0; index<QGroundControl.multiVehicleManager.vehicles.count; index++) {
            if (QGroundControl.multiVehicleManager.vehicles.get(index).parameterManager.pendingWrites) {
                let accepted = false
                _reentrantCloseGuard = true
                _showMessageDialogWorker(mainWindow, qsTr("Pending Parameter Updates"),
                    qsTr("You have pending parameter updates to a vehicle. If you close you will lose changes. Are you sure you want to close?"),
                    Dialog.Yes | Dialog.No,
                    function() { accepted = true; _closeChecksToSkip |= _skipPendingParameterWritesCheckMask; performCloseChecks() },
                    function() { if (!accepted) _reentrantCloseGuard = false },
                    true /* 绕过导航检查 */)
                return false
            }
        }
        return true
    }

    // 检查③：是否还有活动的飞行器连接？
    // 有则询问用户"是否仍要退出"（避免误关导致丢链路）。
    function checkForActiveConnections() {
        if (QGroundControl.multiVehicleManager.activeVehicle) {
            let accepted = false
            _reentrantCloseGuard = true
            _showMessageDialogWorker(mainWindow, qsTr("Active Vehicle Connections"),
                qsTr("There are still active connections to vehicles. Are you sure you want to exit?"),
                Dialog.Yes | Dialog.No,
                function() { accepted = true; _closeChecksToSkip |= _skipActiveConnectionsCheckMask; performCloseChecks() },
                function() { if (!accepted) _reentrantCloseGuard = false },
                true /* 绕过导航检查 */)
            return false
        } else {
            return true
        }
    }

    onClosing: (close) => {
        if (!_forceClose) {
            if (_reentrantCloseGuard) {
                close.accepted = false
                return
            }
            _closeChecksToSkip = 0
            close.accepted = performCloseChecks()
        }
    }

    background: Rectangle {
        anchors.fill:   parent
        color:          QGroundControl.globalPalette.window
    }

    // 主"飞行"视图：实时飞行界面（姿态、地图、遥测、图传视频）。
    // 它是应用启动后的默认页面（visible 默认 true）。
    FlyView {
        id:                     flyView
        objectName:             "mainView_fly"
        anchors.fill:           parent
    }

    // 主"任务规划"视图：航线/航点编辑（默认隐藏，由 showPlanView() 切换显示）
    PlanView {
        id:             planView
        objectName:     "mainView_plan"
        anchors.fill:   parent
        visible:        false
    }

    // 仅供调试的测试工具：在发布构建中不会实例化，且仅在实际显示时
    // 才加载
    Loader {
        id:             geoTestView
        objectName:     "mainView_geoTest"
        anchors.fill:   parent
        visible:        false
        active:         ScreenTools.isDebug && visible
        source:         "qrc:/qml/QGroundControl/GeoMap/GeoMapTestView.qml"
    }

    footer: LogReplayStatusBar {
        visible: QGroundControl.settingsManager.flyViewSettings.showLogReplayStatusBar.rawValue
    }

    MessageDialog {
        id:                 showTouchAreasNotification
        title:              qsTr("Debug Touch Areas")
        text:               qsTr("Touch Area display toggled")
        buttons:            MessageDialog.Ok
    }

    MessageDialog {
        id:                 advancedModeOnConfirmation
        title:              qsTr("Advanced Mode")
        text:               QGroundControl.corePlugin.showAdvancedUIMessage
        buttons:            MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function (button, role) {
            if (button === MessageDialog.Yes) {
                QGroundControl.corePlugin.showAdvancedUI = true
            }
        }
    }

    MessageDialog {
        id:                 advancedModeOffConfirmation
        title:              qsTr("Advanced Mode")
        text:               qsTr("Turn off Advanced Mode?")
        buttons:            MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function (button, role) {
            if (button === MessageDialog.Yes) {
                QGroundControl.corePlugin.showAdvancedUI = false
            }
        }
    }

    function showToolSelectDialog() {
        if (mainWindow.allowViewSwitch()) {
            mainWindow.showIndicatorDrawer(toolSelectComponent, null)
        }
    }

    // 当视图切换被校验错误阻止时显示的提示通知
    ToolTip {
        id:             validationErrorToast
        x:              (mainWindow.width - width) / 2
        y:              mainWindow.height - height - ScreenTools.defaultFontPixelHeight * 3
        timeout:        3000
        closePolicy:    Popup.NoAutoClose
        text:           qsTr("Please correct the invalid value before continuing")

        background: Rectangle {
            color:  qgcPal.alertBackground
            radius: ScreenTools.defaultFontPixelWidth / 2
        }

        contentItem: QGCLabel {
            text:   validationErrorToast.text
            color:  qgcPal.alertText
        }
    }

    Component {
        id: toolSelectComponent

        SelectViewDropdown {
        }
    }

    // 工具抽屉：一个覆盖在主视图之上的"二级页面"容器，
    // 用于承载 分析工具 / 飞控配置 / 应用设置 等页面。
    // 具体内容由 Loader（toolDrawerLoader）按需加载，toolSource 指向对应 QML 文件。
    Rectangle {
        id:             toolDrawer
        objectName:     "mainView_toolDrawer"
        anchors.fill:   parent
        visible:        false
        color:          qgcPal.window

        property var backIcon
        property string toolTitle
        property alias toolSource:  toolDrawerLoader.source   // 别名：把 toolSource 映射到 Loader.source
        property var toolIcon

        // 抽屉关闭时清空已加载的页面，下次打开重新加载
        onVisibleChanged: {
            if (!toolDrawer.visible) {
                toolDrawerLoader.source = ""
            }
        }

        // 需要阻止点击事件泄漏到下层地图。
        // DeadMouseArea 会"吃掉"所有鼠标事件，防止点击穿透到地图上。
        DeadMouseArea {
            anchors.fill: parent
        }

        // 抽屉顶部的工具栏：左侧是 QGC 标志（点击返回工具选择）+ 当前工具标题
        Rectangle {
            id:             toolDrawerToolbar
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    parent.top
            height:         ScreenTools.toolbarHeight
            color:          qgcPal.toolbarBackground

            RowLayout {
                id:                 toolDrawerToolbarLayout
                anchors.leftMargin: ScreenTools.defaultFontPixelWidth
                anchors.left:       parent.left
                anchors.top:        parent.top
                anchors.bottom:     parent.bottom
                spacing:            ScreenTools.defaultFontPixelWidth

                QGCToolBarButton {
                    id: qgcButton
                    objectName: "toolbar_qgcLogo"
                    height: parent.height
                    icon.source: "/res/QGCLogoFull.svg"
                    logo: true
                    onClicked: mainWindow.showToolSelectDialog()
                }

                QGCLabel {
                    id:             toolbarDrawerText
                    text:           toolDrawer.toolTitle
                    font.pointSize: ScreenTools.largeFontPointSize
                }
            }
        }

        Loader {
            id:             toolDrawerLoader
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    toolDrawerToolbar.bottom
            anchors.bottom: parent.bottom
        }
    }

    //-------------------------------------------------------------------------
    //-- 关键飞行器消息弹窗
    // 用于显示飞行器上报的严重警告（例如电池电压过低、GPS 丢失、PreArm 失败等）。
    // C++ 端调用 QGCApplication::showCriticalVehicleMessage 最终会进入这里。

    // 显示一条飞行器关键警告。若警告弹窗已在显示（或视频全屏），
    // 则只置位"还有更多错误"标记，避免覆盖当前正在阅读的警告。
    function showCriticalVehicleMessage(message) {
        if (suppressCriticalVehicleMessages) {
            return
        }
        if (criticalVehicleMessagePopup.visible || QGroundControl.videoManager.fullScreen) {
            // 在旧的警告消息仍显示时收到了额外的警告消息。
            // 当用户关闭旧消息时，收起消息指示工具，以便他们能看到其余消息。
            criticalVehicleMessagePopup.additionalCriticalMessagesReceived = true
        } else {
            criticalVehicleMessagePopup.criticalVehicleMessage      = message
            criticalVehicleMessagePopup.additionalCriticalMessagesReceived = false
            criticalVehicleMessagePopup.open()
        }
    }

    // 关键警告弹窗本体：非模态（modal:false，不阻塞操作）、自动定位在顶部居中。
    // 结构：背景圆角框 + 顶部"Vehicle Error"标签 + 底部"还有更多错误"角标。
    Popup {
        id:                 criticalVehicleMessagePopup
        y:                  ScreenTools.toolbarHeight + ScreenTools.defaultFontPixelHeight
        x:                  Math.round((mainWindow.width - width) * 0.5)
        width:              mainWindow.width  * 0.55
        height:             criticalVehicleMessageText.contentHeight + ScreenTools.defaultFontPixelHeight * 2
        modal:              false
        focus:              true

        property alias  criticalVehicleMessage:             criticalVehicleMessageText.text
        property bool   additionalCriticalMessagesReceived: false

        background: Rectangle {
            anchors.fill:   parent
            color:          qgcPal.alertBackground
            radius:         ScreenTools.defaultFontPixelHeight * 0.5
            border.color:   qgcPal.alertBorder
            border.width:   2

            Rectangle {
                anchors.horizontalCenter:   parent.horizontalCenter
                anchors.top:                parent.top
                anchors.topMargin:          -(height / 2)
                color:                      qgcPal.alertBackground
                radius:                     ScreenTools.defaultFontPixelHeight * 0.25
                border.color:               qgcPal.alertBorder
                border.width:               1
                width:                      vehicleWarningLabel.contentWidth + _margins
                height:                     vehicleWarningLabel.contentHeight + _margins

                property real _margins: ScreenTools.defaultFontPixelHeight * 0.25

                QGCLabel {
                    id:                 vehicleWarningLabel
                    anchors.centerIn:   parent
                    text:               qsTr("Vehicle Error")
                    font.pointSize:     ScreenTools.smallFontPointSize
                    color:              qgcPal.alertText
                }
            }

            Rectangle {
                id:                         additionalErrorsIndicator
                anchors.horizontalCenter:   parent.horizontalCenter
                anchors.bottom:             parent.bottom
                anchors.bottomMargin:       -(height / 2)
                color:                      qgcPal.alertBackground
                radius:                     ScreenTools.defaultFontPixelHeight * 0.25
                border.color:               qgcPal.alertBorder
                border.width:               1
                width:                      additionalErrorsLabel.contentWidth + _margins
                height:                     additionalErrorsLabel.contentHeight + _margins
                visible:                    criticalVehicleMessagePopup.additionalCriticalMessagesReceived

                property real _margins: ScreenTools.defaultFontPixelHeight * 0.25

                QGCLabel {
                    id:                 additionalErrorsLabel
                    anchors.centerIn:   parent
                    text:               qsTr("Additional errors received")
                    font.pointSize:     ScreenTools.smallFontPointSize
                    color:              qgcPal.alertText
                }
            }
        }

        QGCLabel {
            id:                 criticalVehicleMessageText
            width:              criticalVehicleMessagePopup.width - ScreenTools.defaultFontPixelHeight
            anchors.centerIn:   parent
            wrapMode:           Text.WordWrap
            color:              qgcPal.alertText
            textFormat:         TextEdit.RichText
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                criticalVehicleMessagePopup.close()
                if (criticalVehicleMessagePopup.additionalCriticalMessagesReceived) {
                    criticalVehicleMessagePopup.additionalCriticalMessagesReceived = false;
                    flyView.dropMainStatusIndicatorTool();
                } else if (QGroundControl.multiVehicleManager.activeVehicle) {
                    QGroundControl.multiVehicleManager.activeVehicle.resetErrorLevelMessages();
                }
            }
        }
    }

    //-------------------------------------------------------------------------
    //-- 指示抽屉
    // 从顶部工具栏某个"指示图标"位置弹出的浮层（如飞行模式、任务进度等面板）。
    // 打开后由一个 Loader 加载抽屉内容，可展开查看更多。

    // 打开指示抽屉：drawerComponent 是要加载的面板组件，indicatorItem 是触发它的指示图标
    // （用于计算抽屉的弹出位置，让它对准该图标）。
    function showIndicatorDrawer(drawerComponent, indicatorItem) {
        indicatorDrawer.sourceComponent = drawerComponent
        indicatorDrawer.indicatorItem = indicatorItem
        indicatorDrawer.open()
    }

    // 关闭指示抽屉
    function closeIndicatorDrawer() {
        indicatorDrawer.close()
    }

    // 指示抽屉本体：非模态浮层，按触发图标位置水平对齐（calcXPosition），
    // 可通过右上角按钮展开（_expanded）。关闭时释放加载的组件。
    Popup {
        id:             indicatorDrawer
        x:              calcXPosition()
        y:              ScreenTools.toolbarHeight + _margins
        leftInset:      0
        rightInset:     0
        topInset:       0
        bottomInset:    0
        padding:        _margins * 2
        visible:        false
        modal:          true
        focus:          true
        closePolicy:    Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property var sourceComponent
        property var indicatorItem

        property bool _expanded:    false
        property real _margins:     ScreenTools.defaultFontPixelHeight / 4

        function calcXPosition() {
            if (indicatorItem) {
                var xCenter = indicatorItem.mapToItem(mainWindow.contentItem, indicatorItem.width / 2, 0).x
                return Math.max(_margins, Math.min(xCenter - (contentItem.implicitWidth / 2), mainWindow.contentItem.width - contentItem.implicitWidth - _margins - (indicatorDrawer.padding * 2) - (ScreenTools.defaultFontPixelHeight / 2)))
            } else {
                return _margins
            }
        }

        onOpened: {
            _expanded                               = false;
            indicatorDrawerLoader.sourceComponent   = indicatorDrawer.sourceComponent
        }
        onClosed: {
            _expanded                               = false
            indicatorItem                           = undefined
            indicatorDrawerLoader.sourceComponent   = undefined
        }

        background: Item {
            Rectangle {
                id:             backgroundRect
                anchors.fill:   parent
                color:          QGroundControl.globalPalette.window
                radius:         indicatorDrawer._margins
                opacity:        0.85
            }

            Rectangle {
                objectName:                 "indicatorDrawerExpandButton"
                anchors.horizontalCenter:   backgroundRect.right
                anchors.verticalCenter:     backgroundRect.top
                width:                      ScreenTools.largeFontPixelHeight
                height:                     width
                radius:                     width / 2
                color:                      QGroundControl.globalPalette.button
                border.color:               QGroundControl.globalPalette.buttonText
                visible:                    indicatorDrawerLoader.item && indicatorDrawerLoader.item._showExpand && !indicatorDrawer._expanded

                QGCLabel {
                    anchors.centerIn:   parent
                    text:               ">"
                    color:              QGroundControl.globalPalette.buttonText
                }

                QGCMouseArea {
                    fillItem: parent
                    onClicked: indicatorDrawer._expanded = true
                }
            }
        }

        contentItem: QGCFlickable {
            id:             indicatorDrawerLoaderFlickable
            implicitWidth:  Math.min(mainWindow.contentItem.width - (2 * indicatorDrawer._margins) - (indicatorDrawer.padding * 2), indicatorDrawerLoader.width)
            implicitHeight: Math.min(mainWindow.contentItem.height - ScreenTools.toolbarHeight - (2 * indicatorDrawer._margins) - (indicatorDrawer.padding * 2), indicatorDrawerLoader.height)
            contentWidth:   indicatorDrawerLoader.width
            contentHeight:  indicatorDrawerLoader.height

            Loader {
                id:         indicatorDrawerLoader
                objectName: "indicatorDrawerLoader"

                Binding {
                    target:     indicatorDrawerLoader.item
                    property:   "expanded"
                    value:      indicatorDrawer._expanded
                }

                Binding {
                    target:     indicatorDrawerLoader.item
                    property:   "drawer"
                    value:      indicatorDrawer
                }
            }
        }
    }

    // 分析页面项（包括面板内和弹出窗口）都以 mainWindow 作为其
    // QObject 父对象创建，因此其生命周期不绑定于 AnalyzeView。这让弹出的窗口
    // 在 AnalyzeView 从工具抽屉卸载后仍能存活。

    // 跟踪当前显示在 AnalyzeView 面板内的分析页面项（非弹出）。
    // 当没有加载页面或该项已移交给弹出窗口时为 null。
    property var _inPanelAnalyzePage: null

    // 由 AnalyzeView.Component.onDestruction 调用，用于在
    // panelContainer 仍然存活时销毁面板内项。
    function destroyInPanelAnalyzePage() {
        if (_inPanelAnalyzePage) {
            _inPanelAnalyzePage.destroy()
            _inPanelAnalyzePage = null
        }
    }

    // 由 AnalyzeView 调用，创建由 mainWindow 拥有的分析页面项。
    // 调用方在创建后将视觉父对象设置为 panelContainer。
    function createAnalyzePage(source) {
        if (_inPanelAnalyzePage) {
            _inPanelAnalyzePage.destroy()
            _inPanelAnalyzePage = null
        }
        var component = Qt.createComponent(source)
        if (component.status !== Component.Ready) {
            console.warn("createAnalyzePage failed source:", source, "errorString:", component.errorString())
            return null
        }
        _inPanelAnalyzePage = component.createObject(mainWindow)
        return _inPanelAnalyzePage
    }

    // 当面板内项移交给弹出窗口时由 AnalyzeView 调用。
    // 清除 _inPanelAnalyzePage，使 destroyInPanelAnalyzePage() 在
    // AnalyzeView 被销毁时不会销毁它。
    function analyzePageMovedToPopup() {
        _inPanelAnalyzePage = null
    }

    // 创建"独立窗口"形式的分析页面（分析工具可被拖出来变成独立小窗口）。
    //   参数 title：窗口标题；source：要加载的 QML 文件；
    //   requiresVehicle：为 true 时若活动飞行器断开则自动关闭该窗口；
    //   existingItem：若传入一个已存在的页面项，则直接接管它（adoptItem），
    //                 否则按 source 新加载一个页面。
    function createWindowedAnalyzePage(title, source, requiresVehicle, existingItem) {
        var windowedPage = windowedAnalyzePage.createObject(mainWindow)
        windowedPage.title = title
        windowedPage.requiresVehicle = requiresVehicle
        if (existingItem) {
            windowedPage.adoptItem(existingItem)
        } else {
            windowedPage.source = source
        }
        windowedPage.visible = true
    }

    // "独立分析窗口"组件定义：一个独立的 Window（可拖动/缩放的系统窗口），
    // 内部用 Loader 加载分析页面，关闭时清理所有子项后销毁自身。
    Component {
        id: windowedAnalyzePage

        Window {
            width:      ScreenTools.defaultFontPixelWidth  * 100
            height:     ScreenTools.defaultFontPixelHeight * 40
            visible:    false

            property alias source: loader.source
            property bool requiresVehicle: false

            function adoptItem(item) {
                loader.visible = false
                loader.source = ""
                item.parent = contentRect
                item.anchors.fill = contentRect
                item.popped = true
                item.visible = true
            }

            Connections {
                target: QGroundControl.multiVehicleManager
                function onActiveVehicleChanged() {
                    if (requiresVehicle) {
                        close()
                    }
                }
            }

            Rectangle {
                id:             contentRect
                color:          QGroundControl.globalPalette.window
                anchors.fill:   parent

                Loader {
                    id:             loader
                    anchors.fill:   parent
                    onLoaded:       item.popped = true
                }
            }

            onClosing: {
                visible = false
                // 销毁任何被重新指定父对象的子项（不由 loader 所有）
                for (var i = contentRect.children.length - 1; i >= 0; i--) {
                    var child = contentRect.children[i]
                    if (child !== loader) {
                        child.destroy()
                    }
                }
                source = ""
                Qt.callLater(destroy)
            }
        }
    }
}
