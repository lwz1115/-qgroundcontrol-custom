import QGroundControl
import QGroundControl.Controls

/// 无人船：一键清除当前载具已记录的飞行轨迹。
/// 外形与"自动导航/暂停"一致（图标 + 文字竖排），放在暂停按钮下方。
/// 点击直接调用 Vehicle.trajectoryPoints.clear()，QtLocation 与 GeoMap
/// 两套地图都监听 pointsCleared，同步清空红/蓝色轨迹线。
ToolStripAction {
    text:       qsTr("轨迹")
    // 独立图标文件 usv-trashcan.svg：避免与 QGC 原有 TrashCan.svg 在 Windows（大小写不敏感）上同名冲突
    iconSource: "/res/usv-trashcan.svg"
    visible:    !!QGroundControl.multiVehicleManager.activeVehicle
    enabled:    !!QGroundControl.multiVehicleManager.activeVehicle

    onTriggered: {
        const vehicle = QGroundControl.multiVehicleManager.activeVehicle
        if (vehicle && vehicle.trajectoryPoints) {
            vehicle.trajectoryPoints.clear()
        }
    }
}
