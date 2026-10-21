import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// 两点穿梭横移（OMNI X 船形专属）：左下角横移图标，点击展开面板。
///
/// 协议：全部通过 MAV_CMD_USER_1（COMMAND_INT）子命令下发，状态机在飞控侧（AP_Shuttle）：
///   param1=0 查询状态（上报 SHUTTLE_STATE <状态> WP <当前点>，当前点 1=A 2=B）
///   param1=1 停止穿梭（飞控清理任务 → 回 LOITER）
///   param1=2/3 设 A/B 点（x/y = 经纬度；与另一点重复 <2m 拒绝 SHUTTLE_ERR_DUP_AB）
///   param1=4 切换（飞控自动判断：在 A→去 B，在 B→去 A；移动中/任务中拒绝）
///   param1=5 采样任务（飞控模拟 10s，完成上报 SHUTTLE_TASK_DONE）
///   param1=6 测量任务（飞控模拟 5s，完成上报 SHUTTLE_TASK_DONE）
///
/// 面板：
///   - 航点 A / B 下拉 + 「设A / 设B」按钮：把选中航点坐标下发给飞控
///   - 切换：发给飞控，由飞控自动判断目标点，QGC 不自己算
///   - 任务：仅在悬停（HOVER）时可点，采样 / 测量，时长与完成由飞控控制
///   - 停止：飞控清理任务并回 LOITER
///   - 状态显示：完全镜像飞控上报（IDLE / HOVER / MOVING / TASKING / MANUAL_LOCK + 当前点）
///
/// QGC 不持有状态机，只负责“发 USER_1 指令 + 解析 STATUSTEXT 上报”，避免两边状态不一致。
Item {
    id: control

    /// 上层传下来的可用区域（与水质/采样卡片同一套坐标系）
    property var parentToolInsets
    /// 摄像头小窗左上角与宽度，由 FlyViewCustomLayer 提供
    property point pipTopLeft
    property real  pipWidth: 0

    readonly property real _margin:       ScreenTools.defaultFontPixelWidth * 0.75
    /// 卡片边长：与采样卡完全一致（随小窗宽度联动 + 封顶），保证三卡竖排严格对齐
    readonly property real _cardSize:     (_camActive && pipWidth > 0)
                                          ? Math.min(pipWidth * 0.28, ScreenTools.defaultFontPixelHeight * 1.9)
                                          : ScreenTools.defaultFontPixelHeight * 1.7
    readonly property real _spacing:      ScreenTools.defaultFontPixelWidth * 0.25
    readonly property real _pipClearance: ScreenTools.defaultFontPixelWidth * 0.75
    readonly property real _iconX:        control.pipTopLeft.x

    // 横移卡在采样卡上方，形成“横移 / 采样 / 水质”竖排；用 Math.max 兜底，
    // 避免小窗靠顶时三卡被推出屏幕外（采样/水质只算两卡，横移更高一格更容易溢出）。
    readonly property real _iconsTopY: control._camActive
                                        ? Math.max(0, control.pipTopLeft.y - control._cardSize * 3 - control._spacing * 2 - control._pipClearance)
                                        : Math.max(0, parent.height - control._cardSize * 3 - control._spacing * 2 - control._margin)

    /// 摄像头是否在显示（决定卡片贴小窗顶还是落左下角）
    readonly property bool _camActive: QGroundControl.videoManager.isStreamSource
                                        || QGroundControl.videoManager.isUvc

    /// 当前活动载具 / OMNI X 显示条件
    readonly property var  _activeVehicle:    QGroundControl.multiVehicleManager.activeVehicle
    readonly property bool _vehicleConnected: !!_activeVehicle
    readonly property bool _isOmniX:          _activeVehicle ? _activeVehicle.isOmniX : false

    // ---- 航点下拉数据源：飞行界面的任务（已上传/下载生效的那份）----
    readonly property var _flyMissionController: {
        const planController = globals.planMasterControllerFlyView
        return planController ? planController.missionController : null
    }
    readonly property var _waypointItems: {
        // 收集任务里所有带坐标的航点（跳过 home 设置项 index 0）
        const mc = control._flyMissionController
        const result = []
        if (!mc || !mc.visualItems) {
            return result
        }
        for (let i = 1; i < mc.visualItems.count; i++) {
            const item = mc.visualItems.get(i)
            if (item && item.specifiesCoordinate && !item.isStandaloneCoordinate
                    && item.coordinate && item.coordinate.isValid) {
                result.push({ text: qsTr("航点 %1").arg(item.missionItemNumber > 0 ? item.missionItemNumber : item.sequenceNumber),
                              coord: item.coordinate })
            }
        }
        return result
    }

    // ---- 穿梭状态（镜像飞控 AP_Shuttle，QGC 不持有状态机）----
    property int    _state:     -1  ///< 飞控状态：0=IDLE 1=HOVER 2=MOVING 3=TASKING 4=MANUAL_LOCK（-1=未知）
    property int    _currentAt: 0   ///< 当前所在点：0=A 1=B -1=未知
    property string _taskType:  ""  ///< 当前任务类型：sample=采样 measure=测量（仅显示用）
    property string _hintText:  ""  ///< 提示文案（飞控消息 / 本地提示）

    // 航点 A / B 选择（默认 A=第一个，B=最后一个）
    property int _selectedA: 0
    property int _selectedB: _waypointItems.length > 1 ? _waypointItems.length - 1 : 0

    /// 航点 A / B 坐标
    readonly property var _coordA: control._waypointItems.length > control._selectedA ? control._waypointItems[control._selectedA].coord : null
    readonly property var _coordB: control._waypointItems.length > control._selectedB ? control._waypointItems[control._selectedB].coord : null

    /// 距离限制（最小 0.5m / 最大 5000m）
    readonly property real _minDist: 0.5
    readonly property real _maxDist: 5000.0
    readonly property real _abDistance: {
        if (!control._coordA || !control._coordB || !control._coordA.isValid || !control._coordB.isValid) {
            return -1
        }
        const d = control._coordA.distanceTo(control._coordB)
        return isNaN(d) ? -1 : d
    }
    readonly property bool _distOk: control._abDistance >= control._minDist && control._abDistance <= control._maxDist

    /// 面板宽度
    /// 安卓端遥控器屏幕小，宽度上限再压一档（默认字宽 30 倍 + 绝对 400 逻辑像素），
    /// 避免点开面板后几乎占满整屏。
    readonly property real _popupWidth: {
        const maxWidth = Math.max(ScreenTools.defaultFontPixelWidth * 14, width - _margin * 4)
        return Math.min(ScreenTools.defaultFontPixelWidth * 30, Math.min(400, maxWidth))
    }

    /// 当前状态文案（基于飞控上报的 SHUTTLE_STATE / 当前点）
    readonly property string _stateText: {
        switch (control._state) {
        case 1: return control._currentAt === 0 ? qsTr("悬停在 A 点") : qsTr("悬停在 B 点")
        case 2: return control._currentAt === 0 ? qsTr("移动中：前往 B 点") : qsTr("移动中：前往 A 点")
        case 3: return control._taskType === "sample" ? qsTr("采样任务执行中…") : qsTr("测量任务执行中…")
        case 4: return qsTr("手动模式锁定")
        default: return control._currentAt === 0 ? qsTr("穿梭未启动（当前在 A 点）")
                    : control._currentAt === 1 ? qsTr("穿梭未启动（当前在 B 点）")
                    : qsTr("穿梭未启动")
        }
    }

    /// 按钮文案：切换目标 = 飞控自动判断（当前在 A→去 B，在 B→去 A）
    readonly property string _switchText: {
        if (control._state === 2) return qsTr("移动中…")
        if (control._state === 3) return qsTr("任务执行中…")
        return control._currentAt === 0 ? qsTr("切换 → B") : qsTr("切换 → A")
    }

    // ---- 命令下发（全部走 MAV_CMD_USER_1，状态机在飞控侧）----

    /// 下发 A 点：USER_1(param1=2, x=lat, y=lon)
    function _sendSetPointA() {
        const coord = control._coordA
        if (!coord || !coord.isValid) {
            control._hintText = qsTr("A 点坐标无效")
            return
        }
        control._activeVehicle.shuttleSetPointA(coord.latitude, coord.longitude)
    }

    /// 下发 B 点：USER_1(param1=3, x=lat, y=lon)
    function _sendSetPointB() {
        const coord = control._coordB
        if (!coord || !coord.isValid) {
            control._hintText = qsTr("B 点坐标无效")
            return
        }
        control._activeVehicle.shuttleSetPointB(coord.latitude, coord.longitude)
    }

    /// 用户点「切换」：USER_1(param1=4)，飞控自动判断目标点
    /// （当前在 A→去 B，在 B→去 A）；移动中/任务中飞控会拒绝。
    function _onSwitch() {
        if (!control._vehicleConnected || !control._isOmniX) {
            return
        }
        if (control._state === 2 || control._state === 3) {
            return
        }
        if (!control._distOk) {
            control._hintText = control._abDistance < 0
                    ? qsTr("航点坐标无效")
                    : (control._abDistance < control._minDist
                            ? qsTr("两点距离过近（< 0.5m）")
                            : qsTr("两点距离过远（> 5000m）"))
            return
        }
        // 切换前先把当前选中的 A/B 坐标下发给飞控（UI 上不再单独设点按钮，
        // 飞控以最新收到的 A/B 为准做自动判断），再发切换命令。
        control._sendSetPointA()
        control._sendSetPointB()
        control._activeVehicle.shuttleSwitch()
    }

    /// 用户点「停止」：USER_1(param1=1)，飞控清理任务并回 LOITER 悬停
    function _onStop() {
        control._activeVehicle.shuttleStop()
    }

    /// 启动采样任务：USER_1(param1=5) → 飞控模拟 10s，完成上报 SHUTTLE_TASK_DONE。
    /// 飞控要求当前处于悬停态（HOVER），否则返回 SHUTTLE_ERR_NOT_HOVER。
    function _startSampleTask() {
        control._taskType = "sample"
        control._activeVehicle.shuttleStartSampleTask()
    }

    /// 启动测量任务：USER_1(param1=6) → 飞控模拟 5s，完成上报 SHUTTLE_TASK_DONE。
    /// 飞控要求当前处于悬停态（HOVER），否则返回 SHUTTLE_ERR_NOT_HOVER。
    function _startMeasureTask() {
        control._taskType = "measure"
        control._activeVehicle.shuttleStartMeasureTask()
    }

    // ---- 飞控状态 / 消息 同步 ----
    Connections {
        target: control._activeVehicle

        // 飞控状态变化（SHUTTLE_STATE 解析结果）：直接镜像，QGC 不自己推状态
        function onShuttleStateChanged(state) {
            control._state = state
            if (state === 2) {
                control._hintText = ""
            }
        }

        // 飞控上报的当前所在航点
        function onShuttleCurrentWpChanged(wp) {
            control._currentAt = wp
        }

        function onShuttleMessageChanged() {
            const msg = control._activeVehicle.shuttleMessage
            if (!msg) {
                return
            }
            // 手动接管：清本地任务类型缓存，提示复位（飞控侧会锁 MANUAL_LOCK）
            if (msg.indexOf("MANUAL_MODE_OVERRIDE") >= 0) {
                control._taskType = ""
                control._hintText = qsTr("手动模式接管，穿梭已退出")
                return
            }
            // 飞控错误回报（设点重复 / 忙 / 未悬停 / 距离超限）：透传给用户
            if (msg.indexOf("SHUTTLE_ERR_") >= 0) {
                control._hintText = msg
                return
            }
// 设点成功 / 任务完成 / 到点回执：清掉旧提示。
            // 到点（REACHED_WP）后主动向飞控查一次状态，拿到最新的 SHUTTLE_STATE ... WP n，
            // 否则飞控只在查询时上报当前点，UI 的“当前在 A/B”会停在旧值不刷新。
            if (msg.indexOf("SHUTTLE_WP_A_OK") >= 0 || msg.indexOf("SHUTTLE_WP_B_OK") >= 0
                || msg.indexOf("REACHED_WP") >= 0 || msg.indexOf("SHUTTLE_TASK_DONE") >= 0) {
                control._hintText = ""
                if (msg.indexOf("SHUTTLE_TASK_DONE") >= 0) {
                    control._taskType = ""
                }
                if (msg.indexOf("REACHED_WP") >= 0) {
                    control._queryState()
                }
                return
            }
        }

        function onFlightModeChanged() {
            // 飞控已上报 MANUAL_LOCK 时不重复提示
            if (control._state === 4) {
                return
            }
            const mode = control._activeVehicle ? control._activeVehicle.flightMode : ""
            const lower = mode.toLowerCase()
            if (lower.indexOf("manual") >= 0 || lower.indexOf("rc") >= 0 || lower.indexOf("stabilize") >= 0) {
                control._taskType = ""
                control._hintText = qsTr("手动模式接管，穿梭已退出")
            }
        }
    }

    /// 面板打开时向飞控查询一次当前状态（SHUTTLE_STATE / 当前点）
    function _queryState() {
        if (control._vehicleConnected && control._isOmniX) {
            control._activeVehicle.shuttleQueryState()
        }
    }

    // ------------------------------------------------------------------
    // 左下角横移图标（方形卡片，与水质/采样同风格，位于采样卡上方）
    // ------------------------------------------------------------------
    Rectangle {
        id: iconButton

        x:              control._iconX
        y:              control._iconsTopY
        width:          control._cardSize
        height:         control._cardSize
        radius:         ScreenTools.defaultBorderRadius
        color:          Qt.rgba(1, 1, 1, 0.75)
        border.color:   Qt.rgba(0, 0, 0, iconMouseArea.containsMouse ? 0.55 : 0.18)
        border.width:   1
        visible:        control._isOmniX && control._vehicleConnected

        QGCColoredImage {
            anchors.centerIn: parent
            width:            parent.width * 0.66
            height:           parent.height * 0.66
            source:           "/res/shuttle.svg"
            // 深灰色（极简风格），不是纯黑
            color:            "#3C3C3C"
        }

        MouseArea {
            id:           iconMouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (controlPopup.visible) {
                    controlPopup.close()
                } else {
                    controlPopup.open()
                    control._queryState()   // 打开时向飞控查询当前状态 / 所在航点
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // 穿梭控制面板
    // ------------------------------------------------------------------
    Popup {
        id:             controlPopup
        x:              iconButton.x
        y:              Math.max(control._margin, iconButton.y - implicitHeight - control._margin)
        width:          control._popupWidth
        padding:        control._margin
        closePolicy:    Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color:        Qt.rgba(1, 1, 1, 0.82)
            border.color: Qt.rgba(0, 0, 0, 0.2)
            border.width: 1
            radius:       ScreenTools.defaultBorderRadius
        }

        contentItem: ColumnLayout {
            spacing: control._margin

            QGCLabel {
                Layout.fillWidth: true
                text:             qsTr("两点穿梭横移")
                color:            "black"
                font.bold:        true
            }

            // ---- 航点 A / B 同一行：两个下拉框并排（切换时飞控自动用当前 A/B，无需手动设点）----
            RowLayout {
                Layout.fillWidth: true
                spacing:          control._margin

                QGCLabel {
                    text:  qsTr("航点 A")
                    color: Qt.rgba(0, 0, 0, 0.6)
                }
                QGCComboBox {
                    id: comboA
                    Layout.fillWidth: true
                    model: {
                        const names = []
                        for (let i = 0; i < control._waypointItems.length; i++) {
                            names.push(control._waypointItems[i].text)
                        }
                        return names
                    }
                    currentIndex: control._selectedA
                    onActivated: (index) => { control._selectedA = index }
                }

                QGCLabel {
                    text:  qsTr("航点 B")
                    color: Qt.rgba(0, 0, 0, 0.6)
                }
                QGCComboBox {
                    id: comboB
                    Layout.fillWidth: true
                    model: comboA.model
                    currentIndex: control._selectedB
                    onActivated: (index) => { control._selectedB = index }
                }
            }

            // ---- 模拟任务（到达悬停后手动点击触发，飞控模拟时长并上报完成）----
            RowLayout {
                Layout.fillWidth: true
                spacing: control._margin

                QGCButton {
                    Layout.fillWidth: true
                    text:                qsTr("采样（10S）")
                    enabled:             control._vehicleConnected && control._isOmniX
                                          && control._state === 1
                    onClicked:           control._startSampleTask()
                }
                QGCButton {
                    Layout.fillWidth: true
                    text:                qsTr("测量（5S）")
                    enabled:             control._vehicleConnected && control._isOmniX
                                          && control._state === 1
                    onClicked:           control._startMeasureTask()
                }
            }

            // ---- 状态与提示 ----
            QGCLabel {
                Layout.fillWidth: true
                text:             control._stateText
                color:            "black"
                font.bold:        control._state !== 0
            }
            QGCLabel {
                Layout.fillWidth: true
                visible:          control._state === 3
                text:             control._taskType === "sample" ? qsTr("采样任务执行中，等待飞控完成…") : qsTr("测量任务执行中，等待飞控完成…")
                color:            "black"
            }
            QGCLabel {
                Layout.fillWidth: true
                visible:          control._hintText !== ""
                text:             control._hintText
                color:            "#B35C00"
                wrapMode:         Text.WordWrap
            }
            QGCLabel {
                Layout.fillWidth: true
                visible:          !control._distOk && control._coordA && control._coordB
                text:             control._abDistance < control._minDist
                                    ? qsTr("两点距离过近（< 0.5m），无法切换")
                                    : qsTr("两点距离过远（> 5000m），无法切换")
                color:            "#B35C00"
                wrapMode:         Text.WordWrap
            }

            // ---- 切换 / 停止 ----
            RowLayout {
                Layout.fillWidth: true
                spacing: control._margin

                QGCButton {
                    Layout.fillWidth: true
                    text:                control._switchText
                    enabled:             control._vehicleConnected && control._isOmniX
                                          && (control._state === 0 || control._state === 1)
                                          && control._distOk
                    onClicked:           control._onSwitch()
                }

                QGCButton {
                    Layout.fillWidth: true
                    text:                qsTr("停止")
                    enabled:             control._vehicleConnected && control._isOmniX
                                          && control._state !== 0 && control._state !== -1
                    onClicked:           control._onStop()
                }
            }
        }
    }
}
