import QGroundControl
import QGroundControl.Controls

ToolStripAction {
    property int    actionID
    property string message

    property var _guidedController: globals.guidedControllerFlyView

    onTriggered: {
        _guidedController.closeAll()
        // 无人船："自动导航"点击直接启航，不做滑动/长按确认
        if (actionID === _guidedController.actionStartMission) {
            _guidedController.executeAction(actionID)
        } else {
            _guidedController.confirmAction(actionID)
        }
    }
}
