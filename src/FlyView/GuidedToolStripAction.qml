import QGroundControl
import QGroundControl.Controls

ToolStripAction {
    property int    actionID
    property string message

    property var _guidedController: globals.guidedControllerFlyView

    onTriggered: {
        _guidedController.closeAll()
        // 无人船：
        //  - "自动导航"点击直接启航
        //  - "暂停"点击直接切手动模式（让船停下），随后按钮变"继续任务"
        // 两者都不弹确认框 / 滑条
        if (actionID === _guidedController.actionStartMission ||
            actionID === _guidedController.actionPause) {
            _guidedController.executeAction(actionID)
        } else {
            _guidedController.confirmAction(actionID)
        }
    }
}
