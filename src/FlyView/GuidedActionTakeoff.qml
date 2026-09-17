import QGroundControl
import QGroundControl.FlyView

/// 无人船场景：本按钮已由"起飞"改造为"自动导航"，点击后滑动确认即可开始执行当前航线。
GuidedToolStripAction {
    text:       _guidedController.startMissionTitle
    iconSource: "/res/waypoint.svg"
    visible:    _guidedController.showStartMission
    enabled:    _guidedController.showStartMission
    actionID:   _guidedController.actionStartMission
}
