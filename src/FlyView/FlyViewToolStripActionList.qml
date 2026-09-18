import QtQml.Models

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Viewer3D

ToolStripActionList {
    id: _root

    signal displayPreFlightChecklist

    model: [
        Viewer3DShowAction { },
        PreFlightCheckListShowAction { onTriggered: displayPreFlightChecklist() },
        // GuidedActionTakeoff 已改造为"自动导航"（见该文件）
        GuidedActionTakeoff { },
        GuidedActionRTL { },
        GuidedActionPause { },
        // "动作(Actions)"按钮对无人船无意义：从左上角工具条移除，任何场景都不再显示
        FlyViewGripperButton { }
    ]
}
