import QtQml

QtObject {
    property var guidedController

    property bool anyActionAvailable: {
        for (var i = 0; i < model.length; i++) {
            if (model[i].visible)
                return true
        }

        return false
    }

    property var model: [
        // "开始任务"已移到左下角"自动导航"按钮，此处不再重复
        {
            title:      guidedController.continueMissionTitle,
            text:       guidedController.continueMissionMessage,
            action:     guidedController.actionContinueMission,
            visible:    guidedController.showContinueMission
        },
        // “改变高度/改变盘旋半径”对无人船无意义，已移除（GuidedActionsController 里的对应动作逻辑保留）
        {
            title:      guidedController.landAbortTitle,
            text:       guidedController.landAbortMessage,
            action:     guidedController.actionLandAbort,
            visible:    guidedController.showLandAbort
        },
        {
            title:      guidedController.changeSpeedTitle,
            text:       guidedController.changeSpeedMessage,
            action:     guidedController.actionChangeSpeed,
            visible:    guidedController.showChangeSpeed
        }
    ]
}
