import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// 水质采样控制入口：左下角圆形图标，点击展开面板
///
/// 采样为全自动流程：QGC 按下“开始”时依次写瓶号 → 容量 → 触发上升沿，
/// 200 ms 后自动补发中位值（下一次点击才构成新边沿）。之后的放杆 → 开阀选瓶
/// → 抽水 → 停泵 → 延时 → 收杆完全由飞控执行，QGC 仅本地同步计时显示进度。
/// 电磁阀（继电器）由飞控在流程内自动控制，QGC 不直接驱动。
Item {
    id: control

    /// 上层传下来的可用区域（已扣掉工具栏、虚拟摇杆、画中画视频等占位），图标按它避让
    property var parentToolInsets
    /// 摄像头小窗左上角（已换算到本控件坐标系）与宽度，由 FlyViewCustomLayer 提供
    property point pipTopLeft
    property real  pipWidth: 0

    readonly property real _margin:   ScreenTools.defaultFontPixelWidth * 0.75
    readonly property real _iconSize: ScreenTools.defaultFontPixelHeight * 1.7
    readonly property real _leftInset: {
        const insets = parentToolInsets
        return (insets && insets.leftEdgeBottomInset) ? insets.leftEdgeBottomInset : 0
    }
    readonly property real _bottomInset: {
        const insets = parentToolInsets
        return (insets && insets.bottomEdgeLeftInset) ? insets.bottomEdgeLeftInset : 0
    }

    /// 面板宽度：介于水质曲线面板与全宽之间，能放下三个中文按钮
    readonly property real _popupWidth: {
        const maxWidth = Math.max(ScreenTools.defaultFontPixelWidth * 14, width - _margin * 4)
        return Math.min(ScreenTools.defaultFontPixelWidth * 38, maxWidth)
    }

    /// 摄像头是否在显示（主画面有源）。有源时卡片列紧贴小窗顶部，无源时落到屏幕左下角。
    readonly property bool _camActive: QGroundControl.videoManager.isStreamSource
                                        || QGroundControl.videoManager.isUvc
    /// 卡片边长：随摄像头小窗宽度联动（两卡片严格一致），封顶防单边过大
    readonly property real _cardSize:  (_camActive && pipWidth > 0)
                                       ? Math.min(pipWidth * 0.28, ScreenTools.defaultFontPixelHeight * 1.9)
                                       : ScreenTools.defaultFontPixelHeight * 1.7
    /// 卡片间距 / 两卡竖排总高 / 卡片左缘（贴齐小窗左缘）/ 卡片列顶部
    readonly property real _spacing:    ScreenTools.defaultFontPixelWidth * 0.25
    /// 卡片列与摄像头小窗顶的间隙：留出空隙，避免小窗边框/画面遮住卡片
    readonly property real _pipClearance: ScreenTools.defaultFontPixelWidth * 0.75
    readonly property real _rowHeight:  control._cardSize * 2 + control._spacing
    readonly property real _iconX:      control.pipTopLeft.x
    readonly property real _iconsTopY:  control._camActive
                                        ? (control.pipTopLeft.y - control._rowHeight - control._pipClearance)
                                        : (parent.height - control._rowHeight - control._margin - control._bottomInset)

    /// 选中的瓶子（1 或 2）
    property int _selectedBottle: 1
    /// 选中的容量（毫升）
    property int _selectedCapacityMl: 500

    /// 当前活动载具 / 是否已连接
    readonly property var  _activeVehicle:    QGroundControl.multiVehicleManager.activeVehicle
    readonly property bool _vehicleConnected: !!_activeVehicle

    // ---- 以下参数全部来自飞控 WS_*（Vehicle::water* 属性），固件未启用时回落到文档默认值 ----
    /// 船体最大容量（毫升），超过它的容量选项禁用
    readonly property int _maxCapacityMl: _activeVehicle ? _activeVehicle.waterMaxVolume : 2000
    /// 抽水速度（毫升/秒）
    readonly property real _flowRate: {
        const rate = _activeVehicle ? _activeVehicle.waterFlowRate : 0
        return rate > 0 ? rate : 10
    }
    /// 放下杆时间（秒）
    readonly property real _openTime:   _activeVehicle ? _activeVehicle.waterOpenTime : 8
    /// 关泵后延时（秒）
    readonly property real _closeDelay: _activeVehicle ? _activeVehicle.waterCloseDelay : 3
    /// 收杆时间（秒）
    readonly property real _closeTime:  _activeVehicle ? _activeVehicle.waterCloseTime : 8

    /// 固件是否报告完整采样流程（WS_BOTTLE_CHAN 与 WS_VOLUME_CHAN 同时存在，v7+）。
    /// 注意不能用 WS_ENABLE 判断版本：v5 固件也有 WS_ENABLE，但没有完整流程，
    /// 拿它当支持标志会出现“界面在跑、机构没动”。
    readonly property bool _samplingSupported: _activeVehicle ? _activeVehicle.waterSamplingSupported : false
    /// 固件侧总开关 WS_ENABLE 是否为 1（标志参数，任何时候都读得到）
    readonly property bool _samplingEnabled:   _activeVehicle ? _activeVehicle.waterSamplingEnabled : false
    /// WS_VALVE_ENABLE 是否为 1（为 0 时电磁阀强制释放，两个瓶会进同一个瓶）
    readonly property bool _valveEnabled:      !_activeVehicle || _activeVehicle.waterValveEnabled
    /// 全部前置条件满足才允许开始采样
    readonly property bool _canStart:          _vehicleConnected && _samplingSupported && _samplingEnabled
    /// 命令序列正在发送中（来自 Vehicle::waterSamplingBusy）。这是第一层保护，只持续不到 1 秒。
    readonly property bool _busy:              _activeVehicle ? _activeVehicle.waterSamplingBusy : false

    /// 可选容量（数字固定，单位统一用 ML / L，不随语言翻译）
    readonly property var _capacityOptions: [
        { ml: 500,  label: qsTr("500 ml") },
        { ml: 1000, label: qsTr("1000 ml") },
        { ml: 2500, label: qsTr("2500 ml") },
        { ml: 5000, label: qsTr("5000 ml") }
    ]
    /// 抽水秒数 = 容量 ÷ 流速
    readonly property real _pumpSeconds:   control._selectedCapacityMl / control._flowRate

    /// 一次完整采样的预估总时长（s）：放杆 + 抽水 + 关泵延时 + 收杆，再加 10 s 余量。
    /// 阶段消息若在到达“收杆”之前就丢了（stage 5 永远不来），收杆兜底定时器不会启动，
    /// 界面就会永久停在“采样中”、开始按钮全部禁用。这条总时长兜底保证到点必定解锁。
    readonly property int _totalTimeoutMs: Math.ceil(
        (control._openTime + control._pumpSeconds + control._closeDelay + control._closeTime + 10) * 1000)

    /// 自动采样时的兜底总时长：任务里设置的采样容量 QML 侧不知道（可能比面板选择大），
    /// 用船体支持的最大容量（WS_MAX_VOLUME）保守估时，避免兜底比真实流程先到。
    readonly property int _autoTotalTimeoutMs: Math.ceil(
        (control._openTime + control._maxCapacityMl / control._flowRate
         + control._closeDelay + control._closeTime + 10) * 1000)

    /// 采样流程状态：**完全由飞控的 STATUSTEXT 驱动**，QGC 不再本地估算时序。
    /// _stage 的数值与 Vehicle::WaterSamplingStage 一一对应（0=空闲 … 6=完成）。
    readonly property int _stage: control._activeVehicle ? control._activeVehicle.waterSamplingStage : 0
    /// 固件回报的抽水秒数（“WS: pumping %us”）；0 = 还没收到
    readonly property int _fcPumpSeconds: control._activeVehicle ? control._activeVehicle.waterPumpSeconds : 0
    /// 阶段文案表，下标即 _stage 的值
    readonly property var _stageLabels: [
        "",                              // 0 空闲
        qsTr("Bottle selected"),         // 1 WS: bottle %u %uml selected
        qsTr("Lowering sampling rod"),   // 2 WS: rod lowering
        qsTr("Pumping water"),           // 3 WS: pumping %us
        qsTr("Waiting"),                 // 4 WS: volume reached
        qsTr("Retracting sampling rod"), // 5 WS: rod retracting
        qsTr("Sampling finished")        // 6 WS: sample complete
    ]
    /// 有效阶段总数（不含空闲）
    readonly property int _stageCount: 6

    property bool _finished:     false   ///< 本次采样已结束（收到 sample complete，或兜底判定）
    /// 抽水阶段已经过的秒数；用飞控给的时长做插值，避免进度条在长抽水段看起来卡住
    property real _pumpElapsed:  0
    /// 整个采样过程仍在进行
    readonly property bool _samplingActive: control._stage > 0 && !control._finished

    /// 整体进度 0..1：已完成的阶段数 + 抽水段内的插值
    readonly property real _overallProgress: {
        if (control._stage >= control._stageCount) {
            return 1
        }
        if (control._stage <= 0) {
            return 0
        }
        var frac = 0
        if ((control._stage === 3) && (control._fcPumpSeconds > 0)) {
            frac = Math.min(1, control._pumpElapsed / control._fcPumpSeconds)
        }
        return Math.min(1, (control._stage - 1 + frac) / control._stageCount)
    }

    /// 进度条下方显示的当前阶段文案（N/6 阶段名）；空闲时为空
    readonly property string _currentStepText: {
        if (control._stage <= 0) {
            return ""
        }
        return control._stage + "/" + control._stageCount + "  " + control._stageLabels[control._stage]
    }

    /// 总体进度文案：抽水阶段显示固件报的总秒数与已过秒数，其余阶段只显示百分比
    readonly property string _progressText: {
        if ((control._stage === 3) && (control._fcPumpSeconds > 0)) {
            return qsTr("Pumping: %1 s / %2 s")
                .arg(Math.min(control._fcPumpSeconds, Math.round(control._pumpElapsed)))
                .arg(control._fcPumpSeconds)
        }
        return qsTr("Progress: %1%").arg(Math.round(control._overallProgress * 100))
    }

    /// “开始采样”按钮的文案
    readonly property string _startButtonText: {
        if (_finished) {
            return qsTr("Sampling Finished")
        }
        if (_samplingActive) {
            return qsTr("Sampling in progress")
        }
        return qsTr("Start Sampling")
    }

    /// 前置条件不满足时的非模态提示（空串 = 各条件齐备，可以正常采样）
    readonly property string _blockReason: {
        if (!_vehicleConnected) {
            return ""
        }
        if (!_samplingSupported) {
            return qsTr("Firmware reports no water sampling pipeline (WS_BOTTLE_CHAN missing).")
        }
        if (!_samplingEnabled) {
            return qsTr("Water sampling is disabled on the firmware (WS_ENABLE = 0).")
        }
        if (!_valveEnabled) {
            return qsTr("WS_VALVE_ENABLE = 0: both bottles may fill the same bottle.")
        }
        return ""
    }

    /// 抽水阶段计时：用固件报的时长做插值，让进度条在长抽水段仍然可见地前进。
    /// 其它阶段不做插值 —— 固件没给时长，靠猜就会像以前那样和实际动作脱节。
    function _tickPump(dt) {
        if ((control._stage !== 3) || control._finished) {
            return
        }
        control._pumpElapsed += dt
    }

    /// 本次采样结束：解锁界面，允许下一次点击
    function _completeSampling() {
        _fcDoneFallback.stop()
        _totalTimeout.stop()
        _pumpTimer.stop()
        _finished = true
        _pumpElapsed = 0
    }

    /// 回到空闲（飞控端流程无法从外部中止，只能重置界面）
    function _abortLocalCountdown() {
        _fcDoneFallback.stop()
        _totalTimeout.stop()
        _pumpTimer.stop()
        _finished = false
        _pumpElapsed = 0
    }

    /// 飞控回报的阶段变化：进入抽水时清零计时；进入收杆时启动完成兜底
    function _onStageChanged() {
        if (control._stage === 3) {
            control._pumpElapsed = 0
        }
        if (control._stage === 5) {
            // 收杆是最后一步，给固件留出发 sample complete 的时间；超时就兜底解锁，
            // 避免消息在链路上丢了导致界面永久卡在“采样中”
            _fcDoneFallback.interval = (control._closeTime + 5) * 1000
            _fcDoneFallback.restart()
        }
    }

    /// 开始采样：按 瓶号 → 容量 → 触发上升沿 的顺序发三条命令（200 ms 自动松手由 Vehicle 完成）。
    /// 飞控只在触发边沿那一刻读瓶号和容量，顺序不能反。放杆 / 开阀 / 抽水 / 停泵 / 收杆
    /// 全部由飞控执行，QGC 这里只启动本地进度计时。
    /// 任何一条前置条件不满足都要给出可见提示，绝不静默返回（否则用户只看到“点了没反应”）。
    function _startSampling() {
        // 第一层保护：命令序列还在发送中（不到 1 秒）。按钮此时是灰的，这里只是防御。
        if (_busy) {
            QGroundControl.showMessageDialog(control, qsTr("Water Sampling"),
                qsTr("A sampling command sequence is still in progress."), Dialog.Ok)
            return
        }
        // 第二层保护：本次采样还没结束（最长可到 220 秒）。飞控会忽略非空闲态的上升沿，
        // 但本地计时器会从第一步重新开始，导致界面与实际动作脱节，所以在源头挡住。
        if (_samplingActive) {
            return
        }
        if (!_activeVehicle) {
            QGroundControl.showMessageDialog(control, qsTr("Water Sampling"), qsTr("No vehicle connected."), Dialog.Ok)
            return
        }
        if (!_canStart) {
            QGroundControl.showMessageDialog(control, qsTr("Water Sampling"), control._blockReason, Dialog.Ok)
            return
        }
        if (_selectedCapacityMl > _maxCapacityMl) {
            QGroundControl.showMessageDialog(control, qsTr("Water Sampling"),
                qsTr("Selected volume exceeds the vehicle limit (%1 ml).").arg(_maxCapacityMl), Dialog.Ok)
            return
        }

        _finished = false
        _pumpElapsed = 0

        // 总时长兜底：覆盖“阶段消息在中途丢失、永远到不了收杆阶段”的情况，
        // 到点无条件解锁，避免开始按钮被永久禁用。
        _totalTimeout.interval = control._totalTimeoutMs
        _totalTimeout.restart()

        // 只负责发命令；阶段与进度完全由飞控的 STATUSTEXT 驱动，QGC 不再本地估算时序
        _activeVehicle.requestWaterSample(_selectedBottle, _selectedCapacityMl)
    }

    /// 抽水阶段计时：只在飞控已经进入抽水时走，用固件报的时长做进度插值
    Timer {
        id:       _pumpTimer
        interval: 200
        repeat:   true
        running:  control._stage === 3 && !control._finished
        onTriggered: control._tickPump(0.2)
    }

    /// 飞控“采样完成”消息的兜底：进入收杆后迟迟收不到 sample complete 就自己解锁，
    /// 避免界面永久卡在“采样中”（interval 在 _onStageChanged 里按 WS_CLOSE_TIME 设定）
    Timer {
        id:       _fcDoneFallback
        interval: 3000
        repeat:   false

        onTriggered: {
            control._completeSampling()
            QGroundControl.showMessageDialog(control, qsTr("Water Sampling"),
                qsTr("The vehicle did not report sampling completion in time."), Dialog.Ok)
        }
    }

    /// 总时长兜底：开始采样时启动，覆盖“阶段消息在中途丢失、永远到不了收杆阶段”。
    /// 到点只解锁界面、不弹错误框——此时机构到底停在哪一步无法得知，弹框只会误导；
    /// 静默解锁让用户能重新发起一次采样（飞控侧非空闲态会忽略新的触发边沿）。
    Timer {
        id:       _totalTimeout
        repeat:   false

        onTriggered: {
            control._completeSampling()
        }
    }

    // ------------------------------------------------------------------
    // 左下角圆形图标按钮
    // ------------------------------------------------------------------
    Rectangle {
        id: iconButton

        // 方形卡片（与摄像头小窗同风格）：与水质卡片一竖排，采样在上方
        x:              control._iconX
        y:              control._iconsTopY
        width:           control._cardSize
        height:          control._cardSize
        radius:          ScreenTools.defaultBorderRadius
        color:           Qt.rgba(0, 0, 0, 0.6)
        border.color:    Qt.rgba(1, 1, 1, iconMouseArea.containsMouse ? 0.75 : 0.35)
        border.width:    1

        QGCColoredImage {
            anchors.centerIn: parent
            width:            parent.width * 0.58
            height:           parent.height * 0.58
            source:           "/qmlimages/WaterSamplingIcon.svg"
            color:            "white"
        }

        MouseArea {
            id:           iconMouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked:    controlPopup.visible ? controlPopup.close() : controlPopup.open()
        }
    }

    // ------------------------------------------------------------------
    // 控制面板
    // ------------------------------------------------------------------
    Popup {
        id:             controlPopup
        x:              iconButton.x
        y:              Math.max(control._margin, iconButton.y - implicitHeight - control._margin)
        width:          control._popupWidth
        padding:        control._margin
        closePolicy:    Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color:        Qt.rgba(0, 0, 0, 0.85)
            border.color: Qt.rgba(1, 1, 1, 0.25)
            border.width: 1
            radius:       ScreenTools.defaultBorderRadius
        }

        contentItem: ColumnLayout {
            spacing: control._margin

            // ---- 标题 ----
            QGCLabel {
                Layout.fillWidth: true
                text:             qsTr("Water Sampling")
                color:            "white"
                font.bold:        true
            }

            // ---- 瓶子选择：1 号瓶 / 2 号瓶（图标 + 瓶号）----
            QGCLabel {
                text:  qsTr("Bottle")
                color: Qt.rgba(1, 1, 1, 0.7)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing:          control._margin

                Repeater {
                    model: [1, 2]

                    Rectangle {
                        required property var modelData
                        Layout.fillWidth:       true
                        Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 3
                        radius:                 ScreenTools.defaultBorderRadius
                        color:                  Qt.rgba(1, 1, 1, control._selectedBottle === modelData ? 0.28 : 0.08)
                        border.color:           control._selectedBottle === modelData ? "white" : Qt.rgba(1, 1, 1, 0.35)
                        border.width:           1

                        QGCColoredImage {
                            id:                 bottleIcon
                            anchors.centerIn:   parent
                            width:              ScreenTools.defaultFontPixelHeight * 2.2
                            height:             ScreenTools.defaultFontPixelHeight * 2.2
                            source:             "/qmlimages/SampleBottleIcon.svg"
                            color:              "white"
                        }

                        // 瓶号叠加在瓶身中间
                        QGCLabel {
                            anchors.centerIn:  bottleIcon
                            text:              modelData
                            color:             "white"
                            font.bold:         true
                            font.pointSize:    ScreenTools.defaultFontPixelHeight * 0.85
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled:      !control._samplingActive
                            onClicked:    control._selectedBottle = modelData
                        }
                    }
                }
            }

            // ---- 容量选择（超过船体最大容量的选项禁用）----
            QGCLabel {
                text:  qsTr("Capacity")
                color: Qt.rgba(1, 1, 1, 0.7)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing:          control._margin * 0.5

                Repeater {
                    model: control._capacityOptions

                    QGCButton {
                        required property var modelData
                        // 四个按钮等宽：统一的基准宽度 + fillWidth 平分剩余空间
                        Layout.fillWidth:       true
                        Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 5
                        Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 2
                        text:                   modelData.label
                        // 超过船体最大容量 → 禁用
                        enabled:                (modelData.ml <= control._maxCapacityMl) && !control._samplingActive
                        checked:                control._selectedCapacityMl === modelData.ml
                        onClicked:              control._selectedCapacityMl = modelData.ml
                    }
                }
            }

            // ---- 预计抽水时间（容量 ÷ 飞控流速 WS_FLOW_RATE）----
            QGCLabel {
                Layout.fillWidth: true
                text:             qsTr("Estimated pump time: %1 s").arg(Math.round(control._pumpSeconds))
                color:            Qt.rgba(1, 1, 1, 0.7)
                font.pointSize:   ScreenTools.smallFontPointSize * 0.9
            }

            // ---- 前置条件提示（非模态，避免“界面在跑但机构没动”）----
            QGCLabel {
                Layout.fillWidth: true
                visible:             control._blockReason !== ""
                text:                control._blockReason
                color:               "#F5A623"
                wrapMode:            Text.WordWrap
                font.pointSize:      ScreenTools.smallFontPointSize * 0.9
            }

            // ---- 开始采样（全自动流程，飞控接管后无法从外部中止）----
            QGCButton {
                Layout.fillWidth:       true
                Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 2.6
                text:                   control._startButtonText
                // _finished 只决定按钮文字，不能参与 enabled —— 否则采样一次之后按钮永久置灰
                primary:                control._canStart && !control._busy && !control._samplingActive
                enabled:                control._canStart && !control._busy && !control._samplingActive
                onClicked:              control._startSampling()
            }

            Rectangle {
                Layout.fillWidth: true
                height:           1
                color:            Qt.rgba(1, 1, 1, 0.25)
            }

            // ---- 流程显示（进度条 + 当前步骤 + 剩余时间）----

            // 整体进度条
            Item {
                Layout.fillWidth:       true
                Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 0.45

                Rectangle {   // 背景轨道
                    anchors.fill: parent
                    radius:       height / 2
                    color:        Qt.rgba(1, 1, 1, 0.2)
                }

                Rectangle {   // 进度填充
                    anchors.left:   parent.left
                    anchors.top:    parent.top
                    anchors.bottom: parent.bottom
                    width:          parent.width * control._overallProgress
                    radius:         height / 2
                    color:          "#2ECC71"
                }
            }

            // 当前进行中的流程步骤（仅在采样中 / 完成后显示，位于进度条正下方）
            QGCLabel {
                Layout.fillWidth:    true
                visible:             control._samplingActive || control._finished
                horizontalAlignment: Text.AlignHCenter
                font.pointSize:      ScreenTools.defaultFontPixelHeight * 0.55
                font.bold:           true
                text:                control._currentStepText
                color:               "white"
                wrapMode:            Text.WordWrap
            }

            // 总体进度百分比 + 总剩余秒数
            QGCLabel {
                Layout.fillWidth: true
                text:             control._progressText
                color:            Qt.rgba(1, 1, 1, 0.7)
                font.pointSize:   ScreenTools.smallFontPointSize * 0.9
            }
        }
    }

    Component.onCompleted: {
        if (_stage > 0) {
            controlPopup.open()
        }
    }

    // ------------------------------------------------------------------
    // Connections（按 QGC 规范放在可视子项之后）
    // ------------------------------------------------------------------

    // 断线重连 / 车辆切换后：停止本地进度显示并回到初始状态。
    // 注意：飞控端的采样时序无法从外部中止（也没有中止命令），只能重置本地显示。
    Connections {
        target: QGroundControl.multiVehicleManager

        function onActiveVehicleChanged() {
            control._abortLocalCountdown()
        }
    }

    // 飞控的真实反馈。COMMAND_ACK 为 ACCEPTED 并不代表机构动作了：容量信箱没写过、容量超限、
    // 流速非正、通道越界这四种情况下飞控一条机构命令都不执行，却仍回 ACCEPTED。所以必须靠
    // STATUSTEXT 确认（Vehicle 侧解析后发 waterSamplingStarted / Completed / Failed）。
    //
    // 舵机命令的失败不在这里处理：失败码语义（本地去重 / 链路无应答 / 飞控真实拒绝）只有 C++
    // 侧能区分，统一由 waterSamplingFailed 给出准确文案，避免把 QGC 自己的问题栽给飞控。
    Connections {
        target: control._activeVehicle

        function onWaterSamplingStarted() {
            // 手动启动时面板已经打开；任务航点自动采样时也自动展开同一进度面板。
            controlPopup.open()
            // 自动采样同样需要总时长兜底（手动采样已在 _startSampling 里启动）：
            // 阶段消息中途丢失时到点自动解锁，避免界面永久卡在“采样中”。
            if (!_totalTimeout.running) {
                _totalTimeout.interval = control._autoTotalTimeoutMs
                _totalTimeout.restart()
            }
        }

        function onWaterSamplingStageChanged() {
            control._onStageChanged()
            if (control._stage > 0) {
                controlPopup.open()
                // 阶段信号先于 waterSamplingStarted 到达（或该信号漏发）时兜底启动
                if (!_totalTimeout.running && !control._finished) {
                    _totalTimeout.interval = control._autoTotalTimeoutMs
                    _totalTimeout.restart()
                }
            }
        }

        function onWaterSamplingCompleted() {
            // 飞控报告采样完成：正常路径的解锁点
            control._completeSampling()
        }

        function onWaterSamplingFailed(reason) {
            // 没启动成功或中途失败：立刻回滚界面，避免“进度条在走但机构没动”
            control._abortLocalCountdown()
            QGroundControl.showMessageDialog(control, qsTr("Water Sampling"), reason, Dialog.Ok)
        }
    }
}
