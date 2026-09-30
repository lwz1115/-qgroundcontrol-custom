import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FactControls

Rectangle {
    id: _root

    required property var planMasterController
    required property var missionController
    required property var editorMap

    property var _controllerVehicle: planMasterController.controllerVehicle
    property var _visualItems: missionController.visualItems
    property bool _noMissionItemsAdded: _visualItems ? _visualItems.count <= 1 : true
    property var _settingsItem: _visualItems && _visualItems.count > 0 ? _visualItems.get(0) : null
    property bool _multipleFirmware: !QGroundControl.singleFirmwareSupport
    property bool _multipleVehicleTypes: !QGroundControl.singleVehicleSupport
    property bool _allowFWVehicleTypeSelection: _noMissionItemsAdded && !globals.activeVehicle
    property bool _waypointsOnlyMode: QGroundControl.corePlugin.options.missionWaypointsOnly
    property real _fieldWidth: ScreenTools.defaultFontPixelWidth * 16

    width:  parent ? parent.width : 0
    height: mainColumn.height + ScreenTools.defaultFontPixelHeight
    color:  qgcPal.windowShadeDark

    QGCPalette { id: qgcPal; colorGroupEnabled: _root.enabled }

    ColumnLayout {
        id: mainColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: ScreenTools.defaultFontPixelWidth
        spacing: ScreenTools.defaultFontPixelHeight * 0.25

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            QGCLabel {
                text: qsTr("Plan File")
            }

            QGCTextField {
                id: planNameField
                placeholderText: qsTr("Untitled")
                Layout.fillWidth: true

                Component.onCompleted: text = _root.planMasterController.currentPlanFileName

                Connections {
                    target: _root.planMasterController
                    function onCurrentPlanFileNameChanged() {
                        if (!planNameField.activeFocus) {
                            planNameField.text = _root.planMasterController.currentPlanFileName
                        }
                    }
                }

                onEditingFinished: _root.planMasterController.currentPlanFileName = text
            }
        }

        // ── 飞行器信息：无人船专用，直接写死机型 ──
        SectionHeader {
            id: vehicleInfoSectionHeader
            Layout.fillWidth: true
            text: qsTr("飞行器信息")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: ScreenTools.defaultFontPixelWidth
            visible: vehicleInfoSectionHeader.visible && vehicleInfoSectionHeader.checked

            QGCLabel {
                objectName: "planInfo_vehicleTypeLabel"
                text: qsTr("无人船")
                Layout.fillWidth: true
            }
        }

        // ── Expected Home Position（无人船不显示）──
        SectionHeader {
            id: plannedHomePositionSection
            Layout.fillWidth: true
            text: qsTr("Expected Home Position")
            visible: false
        }

        // Prompt to click map to set/move home position
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: ScreenTools.defaultFontPixelWidth / 2
            spacing: ScreenTools.defaultFontPixelWidth / 2
            visible: false

            Image {
                source: "qrc:///qmlimages/MapHome.svg"
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: ScreenTools.defaultFontPixelHeight * 2
                Layout.preferredHeight: Layout.preferredWidth
                fillMode: Image.PreserveAspectFit
            }

            QGCLabel {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Click in map to set position")
                visible: !_root.missionController.homePositionSet
            }

            QGCLabel {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Drag to move home position. Click to set new position.")
                visible: _root.missionController.homePositionSet
            }
        }

        // Normal home position controls (shown only when home is set)
        GridLayout {
            Layout.fillWidth: true
            columnSpacing: ScreenTools.defaultFontPixelWidth
            columns: 2
            visible: false

            QGCLabel {
                text: qsTr("Altitude (AMSL)")
                font.pointSize: ScreenTools.smallFontPointSize
            }
            FactTextField {
                fact: _root._settingsItem ? _root._settingsItem.plannedHomePositionAltitude : null
                Layout.fillWidth: true
                font.pointSize: ScreenTools.smallFontPointSize
                visible: _root._settingsItem && _root._settingsItem.terrainQueryFailed
            }
            QGCLabel {
                text: _root._settingsItem ? _root._settingsItem.plannedHomePositionAltitude.valueString + " " + _root._settingsItem.plannedHomePositionAltitude.units : ""
                Layout.fillWidth: true
                font.pointSize: ScreenTools.smallFontPointSize
                visible: !_root._settingsItem || !_root._settingsItem.terrainQueryFailed
            }
        }

        QGCLabel {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.pointSize: ScreenTools.smallFontPointSize
            text: qsTr("Actual position/alt set by vehicle at flight time.")
            horizontalAlignment: Text.AlignHCenter
            visible: false
        }

        // ── Plan Templates ──
        SectionHeader {
            id: planTemplateSectionHeader
            objectName: "planInfo_templatesSection"
            Layout.fillWidth: true
            text: qsTr("Plan Templates")
            visible: _root.planMasterController.showCreateFromTemplate
        }

        ColumnLayout {
            objectName: "planInfo_templatesColumn"
            Layout.fillWidth: true
            spacing: ScreenTools.defaultFontPixelHeight / 2
            visible: planTemplateSectionHeader.visible && planTemplateSectionHeader.checked
            enabled: _root.missionController.homePositionSet
            opacity: enabled ? 1.0 : 0.5

            Repeater {
                model: _root.planMasterController.planCreators

                QGCButton {
                    objectName: "planCreator_" + object.name
                    Layout.fillWidth: true
                    text: object.name
                    onClicked: {
                        if (object.blankPlan) {
                            _root.planMasterController.userSelectedManualCreation = true
                        } else {
                            object.createPlan(_root.editorMap.center)
                        }
                    }
                }
            }
        }
    }
}
