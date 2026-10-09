import QGroundControl
import QGroundControl.FlyView

/// 无人船场景：本按钮已由"起飞"改造为"自动"，点击直接启航执行当前航线（不再弹确认框）。
GuidedToolStripAction {
    text:       _guidedController.startMissionTitle
    iconSource: "/res/waypoint.svg"
    visible:    _guidedController.showStartMission
    enabled:    _guidedController.showStartMission
    actionID:   _guidedController.actionStartMission
}
