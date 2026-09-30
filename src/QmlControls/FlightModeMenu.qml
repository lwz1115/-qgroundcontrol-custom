import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// Label control whichs pop up a flight mode change menu when clicked
QGCLabel {
    id:     _root
    text:   currentVehicle ? currentVehicle.flightMode : qsTr("N/A", "No data to display")

    property var    currentVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    property real   mouseAreaLeftMargin:    0

    Menu {
        id: flightModesMenu
    }

    Component {
        id: flightModeMenuItemComponent

        MenuItem {
            // 显示中文标签，但下发时用固件的原始模式名（固件只认原始名）
            property string modeName: text
            enabled: true
            onTriggered: currentVehicle.flightMode = modeName
        }
    }

    property var flightModesMenuItems: []

    function updateFlightModesMenu() {
        if (currentVehicle && currentVehicle.flightModeSetAvailable) {
            var i;
            // Remove old menu items
            for (i = 0; i < flightModesMenuItems.length; i++) {
                flightModesMenu.removeItem(flightModesMenuItems[i])
            }
            flightModesMenuItems.length = 0
            // 无人船只保留 4 个模式：手动 / 自动 / 返航 / 悬停，其余不显示。
            // 固件返回的模式名各平台不同（MANUAL/AUTO/RTL/HOLD…），按关键字归类，取首个匹配。
            const modeCatalog = [
                { pattern: /manual/,                             label: qsTr("手动模式") },
                { pattern: /auto/,                               label: qsTr("自动模式") },
                { pattern: /rtl/,                                label: qsTr("返航模式") },
                { pattern: /hold|loiter|position/,               label: qsTr("悬停模式") }
            ];
            const modeNameByKind = [];
            for (i = 0; i < currentVehicle.flightModes.length; i++) {
                const lower = currentVehicle.flightModes[i].toLowerCase();
                for (let k = 0; k < modeCatalog.length; k++) {
                    if (!modeNameByKind[k] && modeCatalog[k].pattern.test(lower)) {
                        modeNameByKind[k] = currentVehicle.flightModes[i];
                        break;
                    }
                }
            }
            // 按目录顺序插入：手动 → 自动 → 返航 → 悬停
            let insertIndex = 0;
            for (let k = 0; k < modeCatalog.length; k++) {
                const modeName = modeNameByKind[k];
                if (modeName !== undefined) {
                    const menuItem = flightModeMenuItemComponent.createObject(null, {
                        "text": modeCatalog[k].label,
                        "modeName": modeName
                    });
                    flightModesMenuItems.push(menuItem);
                    flightModesMenu.insertItem(insertIndex, menuItem);
                    insertIndex++;
                }
            }
        }
    }

    Component.onCompleted: _root.updateFlightModesMenu()

    Connections {
        target:                 QGroundControl.multiVehicleManager
        function onActiveVehicleChanged(activeVehicle) { _root.updateFlightModesMenu() }
    }

    Connections {
        target: currentVehicle
        function onFlightModesChanged() { _root.updateFlightModesMenu() }
    }

    MouseArea {
        id:                 mouseArea
        visible:            currentVehicle && currentVehicle.flightModeSetAvailable
        anchors.leftMargin: mouseAreaLeftMargin
        anchors.fill:       parent
        onClicked:          flightModesMenu.popup((_root.width - flightModesMenu.width) / 2, _root.height)
    }
}
