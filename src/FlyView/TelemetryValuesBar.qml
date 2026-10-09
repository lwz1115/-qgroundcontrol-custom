import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Logging

Item {
    id:             control
    implicitWidth:  mainLayout.width + (_toolsMargin * 2)
    implicitHeight: mainLayout.height + (_toolsMargin * 2)

    property real extraWidth: 0 ///< Extra width to add to the background rectangle

    property var specificVehicleForCard: null

    readonly property real _toolsMargin: ScreenTools.defaultFontPixelWidth * 0.75

    property date _currentTime: new Date()
    property var _vehicle: specificVehicleForCard ? specificVehicleForCard : QGroundControl.multiVehicleManager.activeVehicle
    property var _battery: _vehicle && _vehicle.batteries && _vehicle.batteries.count > 0 ? _vehicle.batteries.get(0) : null

    readonly property string _dateText:         Qt.formatDate(_currentTime, "yyyy-MM-dd")
    readonly property string _timeText:         Qt.formatTime(_currentTime, "HH:mm:ss")
    readonly property string _sessionTimeText:  _formatDuration(_currentTime.getTime() - globals.appStartTime.getTime())
    readonly property string _speedText:        _vehicle && _vehicle.vehicle.groundSpeed ? _vehicle.vehicle.groundSpeed.valueString + " " + _vehicle.vehicle.groundSpeed.units : "--"
    readonly property string _latitudeText:     _vehicle ? _vehicle.latitude.toFixed(6) : "--"
    readonly property string _longitudeText:    _vehicle ? _vehicle.longitude.toFixed(6) : "--"
    readonly property string _voltageText:      _battery && _battery.voltage ? _battery.voltage.valueString + " " + _battery.voltage.units : "--"

    /// 用户设置的自主导航真实速度（m/s）：任务剩余按它预算，而不是 QGC 默认巡航速度
    readonly property real _autonomousNavSpeed: QGroundControl.settingsManager.appSettings.autonomousNavSpeed.value

    /// 飞行中当前正在前往的航点。
    /// 不能用 currentPlanViewItem：MissionController._currentMissionIndexChanged 只更新
    /// isCurrentItem 并发信号，从不调用 setCurrentPlanViewSeqNum，所以它停在规划时选中的那一项，
    /// 船跑到最后一个航点时 distanceFromStart 仍不推进，任务剩余会一直按全程算。
    /// currentMissionIndex 则随 MISSION_CURRENT 实时刷新，这里按序号回查航点。
    readonly property var _activeMissionItem: {
        const mc = control._flyMissionController
        if (!mc || !mc.visualItems) {
            return null
        }
        const seq = mc.currentMissionIndex
        let firstCoordinateItem = null
        let lastCoordinateItem = null
        let nextCoordinateItem = null
        let currentIsDoJump = false
        // 从 index 1 开始：index 0 是 MissionSettingsItem（planned home 位置），
        // 它的 specifiesCoordinate 也是 true，若纳入会把 HOME 当成第 1 个航点，序号错乱。
        for (let i = 1; i < mc.visualItems.count; i++) {
            const item = mc.visualItems.get(i)
            if (!item) {
                continue
            }
            if (item.sequenceNumber === seq && item.command === MAVLinkEnums.MAV_CMD_DO_JUMP) {
                currentIsDoJump = true
            }
            if (!item.specifiesCoordinate) {
                continue
            }
            if (!firstCoordinateItem) {
                firstCoordinateItem = item
            }
            lastCoordinateItem = item
            if (item.sequenceNumber === seq) {
                return item
            }
            if (!nextCoordinateItem && item.sequenceNumber > seq) {
                nextCoordinateItem = item
            }
        }
        // 任务还没开始（MISSION_CURRENT 停在 home/设置项，序号小于第一个航点）：
        // 返回第一个航点，此时剩余距离 = 全任务距离，并含“当前位置到第一个航点”的路程
        if (seq <= (firstCoordinateItem ? firstCoordinateItem.sequenceNumber : 0)) {
            return firstCoordinateItem
        }
        // DO_JUMP 的目标是循环起点；其他非坐标命令之后，目标为序号更大的首个坐标项。
        if (currentIsDoJump) {
            if ((control._totalLoops !== null)
                    && (control._completedLoops >= Number(control._totalLoops))) {
                return lastCoordinateItem
            }
            return firstCoordinateItem
        }
        return nextCoordinateItem || lastCoordinateItem
    }

    /// 当前航点之后所有采样停留时间（s）：真实预算要把停留也加进去
    readonly property real _missionRemainingHoldSeconds: {
        const mc = control._flyMissionController
        if (!mc || !mc.visualItems) {
            return 0
        }
        const current = control._activeMissionItem
        if ((control._totalLoops !== null)
                && (control._completedLoops >= Number(control._totalLoops))) {
            return 0
        }
        let pastCurrent = !current
        let total = 0
        for (let i = 0; i < mc.visualItems.count; i++) {
            const item = mc.visualItems.get(i)
            if (!item) {
                continue
            }
            if (!pastCurrent && item === current) {
                pastCurrent = true
            }
            if (!pastCurrent) {
                continue
            }
            if (item.autoSampleEnabled) {
                total += Number(item.sampleDurationSeconds)
            } else if (item.isSamplePoint && item.holdTimeFact) {
                const hold = Number(item.holdTimeFact.value)
                if (!isNaN(hold) && hold > 0) {
                    total += hold
                }
            }
        }
        return total
    }

    /// 一整圈的全部采样停留时间（s）：剩余圈数 × 这个值 = 后续整圈的停留预算。
    readonly property real _singleLoopHoldSeconds: {
        const mc = control._flyMissionController
        if (!mc || !mc.visualItems) {
            return 0
        }
        let total = 0
        for (let i = 1; i < mc.visualItems.count; i++) {
            const item = mc.visualItems.get(i)
            if (item && item.autoSampleEnabled) {
                total += Number(item.sampleDurationSeconds)
            } else if (item && item.isSamplePoint && item.holdTimeFact) {
                const hold = Number(item.holdTimeFact.value)
                if (!isNaN(hold) && hold > 0) {
                    total += hold
                }
            }
        }
        return total
    }

    /// 从当前位置沿任务航线到末航点的剩余距离（m），不依赖累计 distanceFromStart，
    /// 因为该累计值只对应第一圈，后续循环回到首航点后会给出错误结果。
    readonly property real _remainingThisLoopDistance: {
        const mc = control._flyMissionController
        const items = mc ? mc.visualItems : null
        const current = control._activeMissionItem
        if (!items || !current) {
            return NaN
        }
        const vehicle = control._vehicle
        if (!vehicle || !vehicle.coordinate || !current.entryCoordinate || !current.entryCoordinate.isValid) {
            return NaN
        }
        let total = vehicle.coordinate.distanceTo(current.entryCoordinate)
        if (!isNaN(current.complexDistance)) {
            total += Number(current.complexDistance)
        }
        let previousExit = current.exitCoordinate
        let currentIndex = -1
        for (let i = 1; i < items.count; i++) {
            if (items.get(i) === current) {
                currentIndex = i
                break
            }
        }
        for (let i = currentIndex + 1; i < items.count; i++) {
            const item = items.get(i)
            if (!item || !item.specifiesCoordinate || item.isStandaloneCoordinate) {
                continue
            }
            if (previousExit && previousExit.isValid && item.entryCoordinate && item.entryCoordinate.isValid) {
                total += previousExit.distanceTo(item.entryCoordinate)
            }
            if (!item.isSimpleItem && !isNaN(item.complexDistance)) {
                total += Number(item.complexDistance)
            }
            previousExit = item.exitCoordinate
        }
        return isNaN(total) ? NaN : Math.max(0, total)
    }

    /// DO_JUMP 从末航点回到首航点的闭环距离；QGC 的规划距离不包含这段跳转。
    readonly property real _loopReturnDistance: {
        const items = control._flyMissionController ? control._flyMissionController.visualItems : null
        if (!items) {
            return 0
        }
        let first = null
        let last = null
        for (let i = 1; i < items.count; i++) {
            const item = items.get(i)
            if (item && item.specifiesCoordinate && !item.isStandaloneCoordinate) {
                if (!first) {
                    first = item
                }
                last = item
            }
        }
        if (!first || !last || first === last || !first.entryCoordinate.isValid || !last.exitCoordinate.isValid) {
            return 0
        }
        const distance = last.exitCoordinate.distanceTo(first.entryCoordinate)
        return isNaN(distance) ? 0 : distance
    }

    /// 每个完整后续循环的距离，不含 HOME 到首航点的单次起航段。
    readonly property real _singleLoopDistance: {
        const mc = control._flyMissionController
        const items = mc ? mc.visualItems : null
        if (!mc || !items) {
            return 0
        }
        let first = null
        for (let i = 1; i < items.count; i++) {
            const item = items.get(i)
            if (item && item.specifiesCoordinate && !item.isStandaloneCoordinate) {
                first = item
                break
            }
        }
        const planned = Number(mc.missionPlannedDistance)
        const initialLeg = first ? Number(first.distance) : 0
        if (isNaN(planned) || isNaN(initialLeg)) {
            return 0
        }
        return Math.max(0, planned - initialLeg) + control._loopReturnDistance
    }

    /// 全部任务剩余时间（s）：
    /// 当前圈剩余距离/速度 + 剩余整圈数 × (单圈距离/速度 + 单圈停留) + 当前圈剩余停留。
    /// - 剩余整圈数 = 总圈数 - 已完成圈数 - 1（正在飞的是当前圈，算进“当前圈剩余”里）
    /// - 跳转航点（DO_JUMP）跳回起点：跳过的不产生额外飞行距离，所以后续整圈的距离按
    ///   单圈总距离重复累加即可；跳转本身不增加停留。
    readonly property real _missionRemainingSeconds: {
        const speed = control._autonomousNavSpeed
        if (!speed) {
            return NaN
        }
        const thisLoopDist = control._remainingThisLoopDistance
        if (isNaN(thisLoopDist)) {
            return NaN
        }
        const singleLoopDist = control._singleLoopDistance
        if (isNaN(singleLoopDist)) {
            return NaN
        }
        const totalLoops = control._totalLoops
        // 剩余整圈数：拿不到总圈数时保守当作“至少还有当前圈”，不额外累加整圈。
        // 用 Math.max(0, …) 兜住“已完成圈数已经超过总圈数”的抖动（重连、任务重载时可能出现），
        // 否则会算出负的整圈数把剩余时间压成一段航程——表现为一到末航点剩余时间就塌缩。
        const fullLoopsRemaining = (totalLoops === null)
                ? 0
                : Math.max(0, Math.ceil(Number(totalLoops)) - control._completedLoops - 1)

        let seconds = thisLoopDist / speed
        seconds += control._missionRemainingHoldSeconds
        seconds += fullLoopsRemaining * (singleLoopDist / speed + control._singleLoopHoldSeconds)
        return Math.max(0, seconds)
    }

    /// 任务预估剩余时间：全部循环 + 跳转 + 采样停留都算进去，格式 HH:MM:SS。
    /// 到终点（剩余距离 < 1 米）时归零显示 00:00:00。
    readonly property string _missionRemainingText: {
        const speed = control._autonomousNavSpeed
        const dist = control._remainingThisLoopDistance
        if (!speed || isNaN(dist)) {
            return "--"
        }
        if (dist < 1.0 && control._missionRemainingSeconds < 1.0) {
            return "00:00:00"
        }
        const total = Math.floor(control._missionRemainingSeconds)
        const h = Math.floor(total / 3600)
        const m = Math.floor((total % 3600) / 60)
        const sec = total % 60
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m + ":" + (sec < 10 ? "0" : "") + sec
    }
    /// 到下一个航点的距离：用当前航点坐标与船当前位置直接算（米）。
    /// 不依赖 NAV_CONTROLLER_OUTPUT.wp_dist：USV 固件大概率不发该消息，fact 恒为 0。
    readonly property string _nextWaypointText: {
        const vehicle = control._vehicle
        const item = control._activeMissionItem
        if (!vehicle || !item || !vehicle.coordinate || !item.coordinate || !item.coordinate.isValid) {
            return "--"
        }
        const d = vehicle.coordinate.distanceTo(item.coordinate)
        return isNaN(d) ? "--" : d.toFixed(1) + " m"
    }

    // 计数用的控制器：飞行视图那份，实时跟踪载具 MISSION_CURRENT（规划视图那份只跟编辑内容，不能用来算圈）
    readonly property var _flyMissionController: {
        const planController = globals.planMasterControllerFlyView
        return planController ? planController.missionController : null
    }

    // 总圈数只看“已上传生效”的那份：飞行界面控制器里的任务（上传/下载后会刷成船上的值），
    // 规划界面里改了但没上传的循环次数不参与显示
    readonly property var _missionLoopCount: {
        const missionController = control._flyMissionController
        if (!missionController || missionController.visualItems.count === 0) {
            return null
        }
        const settingsItem = missionController.visualItems.get(0)
        return (settingsItem && settingsItem.loopCount) ? settingsItem.loopCount.rawValue : null
    }

    // 起点序号 = 任务里第一个“带坐标”的项，也就是第一个航点
    // （DO_JUMP / RTL 都不是坐标项，会被自动跳过）。不能写死 items.get(1)：
    // 前面若排了相机、速度等非坐标命令，下标 1 就不是第一个航点，起点取错会让“跳回起点”这段计不上圈。
    // 从下标 1 开始扫：下标 0 固定是任务设置项（它也代表 home，同样算坐标项）；找不到返回 -1。
    readonly property int _loopStartIndex: {
        const items = control._flyMissionController ? control._flyMissionController.visualItems : null
        if (!items || items.count < 2) {
            return -1
        }
        for (let i = 1; i < items.count; i++) {
            const item = items.get(i)
            if (item && item.specifiesCoordinate) {
                return item.sequenceNumber
            }
        }
        return -1
    }

    /// 该 visualItem 是否是 DO_JUMP 动作项（MissionSettingsItem 等没有 command 属性，必须先去判断类型，
    /// 否则 undefined 对比会把设置项误当成 DO_JUMP）
    function _isDoJumpItem(item) {
        return item && (typeof item.command === "number") && (item.command === MAVLinkEnums.MAV_CMD_DO_JUMP)
    }

    // 终点锚点 = 任务末尾的 DO_JUMP 项：ArduPilot 每一圈都必经它
    // （中间圈到达它 → 跳回起点；末圈到达它 → 跳次耗尽、任务结束）。
    // 兼容不循环的单次任务：没有 DO_JUMP 时退回“最后一个坐标航点”。
    readonly property int _loopEndIndex: {
        const items = control._flyMissionController ? control._flyMissionController.visualItems : null
        if (!items || items.count < 2) {
            return -1
        }
        let doJumpIndex = -1
        let lastWaypointIndex = -1
        // 从 index 1 开始：index 0 是 MissionSettingsItem（planned home），不是航点
        for (let i = 1; i < items.count; i++) {
            const item = items.get(i)
            if (!item) {
                continue
            }
            if (control._isDoJumpItem(item)) {
                doJumpIndex = item.sequenceNumber
            } else if (item.specifiesCoordinate) {
                lastWaypointIndex = item.sequenceNumber
            }
        }
        return (doJumpIndex >= 0) ? doJumpIndex : lastWaypointIndex
    }

    // 锚点是否来自任务末尾的 DO_JUMP：只有它才能“到达即判定任务结束”；
    // 单次任务回退到坐标航点时，MISSION_CURRENT 是“开始前往”就上报，必须等序号稳定后再确认
    readonly property bool _loopEndIsDoJump: {
        const items = control._flyMissionController ? control._flyMissionController.visualItems : null
        if (!items || items.count < 2) {
            return false
        }
        for (let i = 0; i < items.count; i++) {
            if (control._isDoJumpItem(items.get(i))) {
                return true
            }
        }
        return false
    }

    // 最后一个坐标航点的序号：末圈跑到它以后船就停在那里（DO_JUMP 跳次已耗尽），
    // 用它配合完成确认定时器判定“任务真的跑完了”
    readonly property int _loopLastWaypointIndex: {
        const items = control._flyMissionController ? control._flyMissionController.visualItems : null
        if (!items || items.count < 2) {
            return -1
        }
        let lastWaypointIndex = -1
        // 从 index 1 开始：index 0 是 MissionSettingsItem（planned home），不是航点
        for (let i = 1; i < items.count; i++) {
            const item = items.get(i)
            if (item && !control._isDoJumpItem(item) && item.specifiesCoordinate) {
                lastWaypointIndex = item.sequenceNumber
            }
        }
        return lastWaypointIndex
    }

    property int    _completedLoops:   0      ///< 已完成的圈数：每到达一次末尾 DO_JUMP（或它跳回起点）即 +1
    property int    _lastMissionIndex: -1     ///< 上一次的 MISSION_CURRENT 序号
    property bool   _loopRunActive:    false  ///< 本趟是否已起步：起步后才允许计圈
    property bool   _taskCompleted:    false  ///< 本趟任务已跑满总圈数并结束（无 UI 提示，仅供上传拦截使用）
    property string _loopMissionKey:   ""     ///< 本趟任务的特征（起点/终点/总圈数），用来识别“任务是否被替换”
    property int    _stationaryRetries: 0     ///< 完成确认时连续判为“未停稳”的次数
    property int    _reachedMaxIndex: -1      ///< 本趟已飞到的最大序号：防止同一圈被序号抖动重复计圈
    property bool   _loopEndArmed:   false    ///< 本趟已到达末尾锚点（DO_JUMP 或末航点）：只有到达过末尾才允许计圈
    /// 总圈数（船上已生效值），可能为 null（拿不到时仍计圈，但不判定完成）
    readonly property var _totalLoops: control._missionLoopCount

    /// 完成确认超时：跑满总圈数、或末圈停在终点后序号长时间不变，就确认任务已结束
    readonly property int _taskCompleteConfirmTimeoutMs: 8000

    /// 停稳判定阈值（m/s）：低于此速度视为停稳
    readonly property real _stationarySpeedThreshold: 0.5

    /// 完成确认时最多容忍多少次“仍在移动”：超过就强制判定完成。
    /// 8 秒一次 × 6 次 ≈ 48 秒，足够慢速船停稳；再久就是永远停不下来，不能再等。
    readonly property int _stationaryConfirmMaxRetries: 6

    /// 任务运行中：已解锁 + 处于任务模式。
    /// 与 MissionController::sendToVehiclePreCheck 的 armed+missionFlightMode 判定保持一致，两处若改动需同步。
    readonly property bool _missionRunning: {
        const vehicle = control._vehicle
        return vehicle ? (vehicle.armed && (vehicle.flightMode === vehicle.missionFlightMode)) : false
    }

    // 显示“已循环次数/总次数”，例如 3/5；拿不到总次数时显示 “--”
    readonly property string _loopCountText: _missionLoopCount === null ? "--" : (_completedLoops + "/" + _missionLoopCount)

    /// 任务特征：起点/终点/总圈数一致就认为是同一个任务。
    /// 总圈数可能取不到（null），这里归一化为 -1：否则 null ↔ 有值之间抖动会让特征对不上、误清零。
    function _loopMissionKeyOf() {
        return control._loopStartIndex + ":" + control._loopEndIndex + ":" + (control._missionLoopCount === null ? -1 : control._missionLoopCount)
    }

    /// 把“任务运行中/已完成”写回飞行界面的任务控制器，供规划界面拦截“任务执行中下发新任务”。
    /// 只在主遥测栏写（多机卡片不写），避免多机时相互覆盖。
    function _publishTaskState() {
        if (specificVehicleForCard) {
            return
        }
        const planController = globals.planMasterControllerFlyView
        if (planController) {
            // 任务已判完成后不再算“运行中”，否则停在总圈数上仍处于任务模式时会一直拦着不让上传新任务
            planController.missionTaskRunning = control._missionRunning && !control._taskCompleted
            planController.missionTaskCompleted = control._taskCompleted
        }
    }

    // 回到“本趟还没起步”的状态，计数清零
    function _resetLoopProgress() {
        _completedLoops = 0
        _lastMissionIndex = -1
        _loopRunActive = false
        _taskCompleted = false
        _stationaryRetries = 0
        _reachedMaxIndex = -1
        _loopEndArmed = false
        _loopMissionKey = control._loopMissionKeyOf()
        completeConfirmTimer.stop()
        control._publishTaskState()
    }

    // 计圈规则：锚点是任务末尾的 DO_JUMP（MISSION_CURRENT 是“开始前往该航点”时上报）。
    //   a) 起步：本趟未起步且序号已进入任务范围 → 清零重计
    //   b) 新一趟：本趟已完成、又回到起点 → 清零重计
    //   c) 到达锚点：序号等于末尾 DO_JUMP 且上一次不是它 → 完成一圈（末圈跑到它说明跳次已耗尽）
    //   d) 从航尾直接回到起点：等价于“DO_JUMP 已经执行过”（带 DO_JUMP 的任务只有它能跳回起点），
    //      按同一件事计一圈（有些固件不单独上报 DO_JUMP 序号）
    //   e) 末圈停在终点：差最后一圈且序号稳定停在终点区域 → 启动完成确认，确认后补上末圈
    //   f) 圈数已满但未确认（单次任务没有 DO_JUMP 时）→ 序号稳定后确认完成
    //   g) 其余只记录上一次序号（跳点不改圈次）
    function _updateLoopProgress(missionIndex) {
        // 只要起点有效即可计圈：终点锚点异常时不应把整个计圈停掉（兜底分支仍可用）
        if (_loopStartIndex < 0) {
            return
        }

        // 诊断开关：沿用 PlanMasterController 日志分类（设置页里的全名就是它）
        if (QGCLoggingCategoryManager.isCategoryEnabled("PlanManager.PlanMasterController")) {
            console.log("TelemetryValuesBar loopProgress index", missionIndex,
                        "start", _loopStartIndex, "end", _loopEndIndex, "lastWp", _loopLastWaypointIndex,
                        "total", _totalLoops, "done", _completedLoops, "active", _loopRunActive, "completed", _taskCompleted)
        }

        // 序号一变说明船还在动，取消上一次的完成确认
        completeConfirmTimer.stop()

        // 本趟已经飞到的最大序号：与末航点序号一起用来判断“这一圈是不是真的跑完了”。
        // 不拿它当计圈的必要条件——有些固件不上报 DO_JUMP 的序号，用它做硬性门槛会一圈都不加。
        if (missionIndex > _reachedMaxIndex) {
            _reachedMaxIndex = missionIndex
        }

        if (!_loopRunActive) {
            if (missionIndex >= _loopStartIndex) {
                _resetLoopProgress()
                _loopRunActive = true
                control._publishTaskState()
            }
        } else if (_taskCompleted && (missionIndex === _loopStartIndex)) {
            _resetLoopProgress()
            _loopRunActive = true
            control._publishTaskState()
        } else if ((missionIndex === _loopStartIndex) && (_lastMissionIndex > _loopStartIndex) && _loopEndArmed) {
            // 回到起点：这一圈真正结束了（跑过末尾锚点才计，见下方 armed 置位）。
            // 手动“跳转航点”回到首航点也会走到这：它不代表跑完一圈，必须用
            // _loopEndArmed（本趟真到过末尾）拦掉，否则 _completedLoops 虚增、
            // 剩余时间会凭空少一整圈。
            _loopEndArmed = false
            control._completeOneLoop()
        } else if ((missionIndex === _loopLastWaypointIndex) && (_lastMissionIndex !== _loopLastWaypointIndex)) {
            // 末圈跑到最后一个航点后停住：等完成确认
            control._armFinalConfirm()
        } else if ((_loopLastWaypointIndex >= 0) && (_totalLoops !== null) && (_completedLoops === (_totalLoops - 1)) && (missionIndex > _loopLastWaypointIndex) && !_taskCompleted) {
            // 末圈后任务越过最后一个坐标航点（返回 HOME / 结束动作，序号比最后航点还大）：
            // 只有 DO_JUMP 跳次耗尽才会走到这里，说明末圈真的跑完了。
            // 此前末圈靠“序号停在终点”的定时器确认，一旦执行返回 HOME 序号会继续往前走、
            // 定时器被取消，所以这里直接把末圈补上并判完成。
            // !_taskCompleted 是幂等闸：返回 HOME 过程中序号每进一步都会走到这个分支，
            // 没有它就会把圈数反复 +1，剩余时间随之塌缩。
            control._handleTaskConfirmed()
        } else if (!_taskCompleted && (_totalLoops !== null) && (_completedLoops >= _totalLoops)) {
            // 圈数已满但还没确认完成（单次任务到达终点却仍在上报序号）：序号稳定后即确认
            completeConfirmTimer.restart()
        }

        // 到达“末尾 DO_JUMP”或“最后一个坐标航点”都视为本圈真正跑到了尾，
        // 置位后下一圈“回到起点”分支才能计圈。末圈返回 HOME 的序号不经过末尾锚点，
        // 由上面的返回 HOME 分支直接处理，不走这里。
        if ((missionIndex === _loopEndIndex) || (missionIndex === _loopLastWaypointIndex)) {
            _loopEndArmed = true
        }

        _lastMissionIndex = missionIndex
    }

    /// 完成一圈：计数 +1；跑满总圈数时：
    ///   · 有 DO_JUMP → 到达它说明跳次已耗尽，立即判定完成（并由完成确认发通知）
    ///   · 单次任务（无 DO_JUMP，锚点是坐标航点）→ 序号只是“开始前往终点”就上报，
    ///     不能立即判定完成，交给完成确认定时器等序号稳定后再判定
    function _completeOneLoop() {
        // 幂等：同一圈只计一次。任务末尾返回 HOME / RTL 时序号会继续递增，
        // 若没有这道闸，已计满的圈会被反复 +1，剩余时间里的“剩余整圈数”被压成 0，
        // 表现为每次飞往末航点时剩余时间塌缩成只剩这一段航程。
        if (_taskCompleted) {
            return
        }
        _completedLoops++
        if ((_totalLoops === null) || (_completedLoops < _totalLoops)) {
            return
        }
        if (_loopEndIsDoJump) {
            _taskCompleted = true
        }
        completeConfirmTimer.restart()
        control._publishTaskState()
    }

    /// 末圈（差最后一圈）停在终点区域时启动完成确认：序号长时间不再变化就认为任务已结束
    function _armFinalConfirm() {
        if (_taskCompleted || (_totalLoops === null)) {
            return
        }
        if (_completedLoops !== (_totalLoops - 1)) {
            return
        }
        completeConfirmTimer.restart()
    }

    // 完成确认超时：① 只在“还差圈数”时补上末圈（已计满不再 +1，避免末圈双计）；
    // ② 判定任务已完成（仅作为状态，不再弹任何提示）。
    // 只是一次性的完成确认，不是周期轮询任务，也不触发任何上传。
    // 注：停船/保位/切动力/上报 COMPLETED 由飞控负责（DO_JUMP 跳次耗尽后不再跳回）；
    // 若某些固件需要 QGC 主动下发 HOLD/暂停命令，可在这个函数里补（飞控端需配合上报 COMPLETED）。
    function _handleTaskConfirmed() {
        // 幂等：已经判完成就不再补圈。任务末尾的返回 HOME / RTL 会让序号持续递增，
        // 分支 e 与完成确认定时器都可能重复调到它。
        if (_taskCompleted) {
            return
        }
        // 只有停稳后才确认完成：单次任务没有 DO_JUMP 时，MISSION_CURRENT 在“开始前往终点”就上报，
        // 慢速船这时往往还在半路，光靠 8 秒定时器会提前判完成。仍在移动就继续等，慢速船不会误判。
        // 连续多次仍判为“未停稳”（水流/风推着船，或 GPS 速度噪声）时：
        //   · 船已到过末航点（_reachedMaxIndex 已覆盖）→ 判定任务确实结束，强制确认，
        //     否则定时器会无限自我重启，任务永远判不了完成，missionTaskRunning 一直为真，
        //     规划界面会一直拦着“任务执行中，不能下发新任务”。
        //   · 还没到过末航点（任务中途）→ 不能靠地速噪声把任务提前判完成，继续等停稳。
        const vehicle = control._vehicle
        const groundSpeedFact = vehicle ? vehicle.vehicle.groundSpeed : null
        if (groundSpeedFact && (groundSpeedFact.value > control._stationarySpeedThreshold)) {
            _stationaryRetries++
            if (_stationaryRetries < control._stationaryConfirmMaxRetries) {
                completeConfirmTimer.restart()
                return
            }
            // 重试耗尽仍“未停稳”：只有任务已到达末航点才强制确认完成
            if (_reachedMaxIndex < control._loopLastWaypointIndex) {
                completeConfirmTimer.restart()
                return
            }
            _stationaryRetries = 0
        } else {
            _stationaryRetries = 0
        }
        if ((_totalLoops !== null) && (_completedLoops < _totalLoops)) {
            _completedLoops++
        }
        _taskCompleted = true
        control._publishTaskState()
    }

    Timer {
        id: completeConfirmTimer
        interval: control._taskCompleteConfirmTimeoutMs
        onTriggered: control._handleTaskConfirmed()
    }

    // 解锁/飞行模式变化时同步“任务运行中”状态（用于拦截任务执行中下发新任务）
    on_MissionRunningChanged: control._publishTaskState()

    // visualItems 重建时是否清零见 _checkMissionReplaced()：
    // 同一个任务（重连、重新下载、任务执行中重载）保持已跑圈数；
    // 只有“上传”才会清零（见下面的 missionUploadComplete 信号）。
    // 也刻意不在载具上锁时清零，否则“停到终点”后看不到 3/3。
    Connections {
        target: control._flyMissionController

        function onCurrentMissionIndexChanged(missionIndex) {
            control._updateLoopProgress(missionIndex)
        }
        function onVisualItemsReset() {
            // 等绑定刷新到新任务的值以后再比较任务特征
            Qt.callLater(control._checkMissionReplaced)
        }
    }

    // 只有“上传”才清零计圈（上传即视为新任务）：重连、重新下载都保持已跑圈数。
    // 单纯看 visualItems 重建区分不出上传与下载，所以要靠这个只在上传完成时发出的信号。
    Connections {
        target: globals.planMasterControllerFlyView

        function onMissionUploadComplete() {
            control._resetLoopProgress()
        }
    }

    /// 任务被替换后：起点/终点/总圈数变了才清零，同一个任务（重连、重下载）保持已跑圈数。
    /// 断连时任务会被清空（特征无效），这时必须保留已跑圈数，否则重连后计数就丢了。
    function _checkMissionReplaced() {
        if ((control._loopStartIndex < 0) || (control._loopEndIndex < 0)) {
            return
        }
        const missionKey = control._loopMissionKeyOf()
        if (missionKey !== control._loopMissionKey) {
            control._resetLoopProgress()
        }
    }

    readonly property real _labelWidth: labelFontMetrics.widestLabelWidth
    // 值列只是“最短宽度”：内容更长时列会自己撑开，不会裁剪，也不会把字体拉伸变形
    readonly property real _valueWidth: ScreenTools.defaultFontPixelWidth * 8

    function _formatDuration(milliseconds) {
        const totalSeconds = Math.max(0, Math.floor(milliseconds / 1000))
        const seconds = totalSeconds % 60
        const minutes = Math.floor(totalSeconds / 60) % 60
        const hours = Math.floor(totalSeconds / 3600)
        return _twoDigits(hours) + ":" + _twoDigits(minutes) + ":" + _twoDigits(seconds)
    }

    function _twoDigits(value) {
        return value < 10 ? "0" + value : String(value)
    }

    Timer {
        interval:         1000
        repeat:           true
        triggeredOnStart: true
        running:          control.visible
        onTriggered:      control._currentTime = new Date()
    }

    /// Label column width, so the trailing colons line up across all rows in every language.
    FontMetrics {
        id: labelFontMetrics

        font.pointSize: ScreenTools.defaultFontPointSize
        font.family:    ScreenTools.normalFontFamily

        readonly property real widestLabelWidth: Math.max(
            advanceWidth(qsTr("Loops:")), advanceWidth(qsTr("Session Time:")),
            advanceWidth(qsTr("Mission Left:")), advanceWidth(qsTr("Next WP:")))
    }

    Rectangle {
        id:         backgroundRect
        width:      control.width + extraWidth
        height:     control.height
        color:      qgcPal.window
        radius:     ScreenTools.defaultFontPixelWidth / 2
        opacity:    0.75
    }

    ColumnLayout {
        id:                 mainLayout
        anchors.margins:    _toolsMargin
        anchors.bottom:     parent.bottom
        anchors.left:       parent.left

        GridLayout {
            columns: 4
            // 安卓上默认间距显得松散：收紧列间距；标签仍右对齐，冒号保持上下对齐
            columnSpacing: ScreenTools.defaultFontPixelWidth * 0.5
            rowSpacing: ScreenTools.defaultFontPixelHeight * 0.2

            QGCLabel { text: qsTr("Speed:");         Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._speedText;      Layout.preferredWidth: control._valueWidth }
            QGCLabel { text: qsTr("Session Time:");  Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._sessionTimeText; Layout.preferredWidth: control._valueWidth }

            QGCLabel { text: qsTr("Longitude:");     Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._longitudeText;  Layout.preferredWidth: control._valueWidth }
            QGCLabel { text: qsTr("Latitude:");      Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._latitudeText;   Layout.preferredWidth: control._valueWidth }

            QGCLabel { text: qsTr("Loops:");         Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._loopCountText;  Layout.preferredWidth: control._valueWidth }
            QGCLabel { text: qsTr("Voltage:");       Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._voltageText;    Layout.preferredWidth: control._valueWidth }

            QGCLabel { text: qsTr("Time:");          Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._timeText;       Layout.preferredWidth: control._valueWidth }
            QGCLabel { text: qsTr("Date:");          Layout.preferredWidth: control._labelWidth; horizontalAlignment: Text.AlignRight }
            QGCLabel { text: control._dateText;       Layout.preferredWidth: control._valueWidth }

            // 无人船：任务剩余时间 + 下一航点距离（接在时间/日期下面，格式一致）
            QGCLabel {
                text: qsTr("Mission Left:")
                Layout.preferredWidth: control._labelWidth
                horizontalAlignment: Text.AlignRight
            }
            QGCLabel { text: control._missionRemainingText; Layout.preferredWidth: control._valueWidth }
            QGCLabel {
                text: qsTr("Next WP:")
                Layout.preferredWidth: control._labelWidth
                horizontalAlignment: Text.AlignRight
            }
            QGCLabel { text: control._nextWaypointText;    Layout.preferredWidth: control._valueWidth }
        }
    }

}
