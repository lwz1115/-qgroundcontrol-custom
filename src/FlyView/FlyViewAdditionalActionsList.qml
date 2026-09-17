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
        {
            title:      guidedController.changeAltTitle,
            text:       guidedController.changeAltMessage,
            action:     guidedController.actionChangeAlt,
            visible:    guidedController.showChangeAlt
        },
        {
            title:      guidedController.changeLoiterRadiusTitle,
            text:       guidedController.changeLoiterRadiusMessage,
            action:     guidedController.actionChangeLoiterRadius,
            visible:    guidedController.showChangeLoiterRadius
        },
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
