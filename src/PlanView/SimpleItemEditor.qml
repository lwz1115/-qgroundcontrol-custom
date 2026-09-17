import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FactControls

// Editor for Simple mission items
Rectangle {
    required property var missionItem
    required property real availableWidth

    id: root
    width: availableWidth
    height: editorColumn.height + (_margin * 2)
    color: qgcPal.windowShadeDark
    radius: _radius


    property bool _specifiesAltitude: missionItem.specifiesAltitude
    property real _margin: ScreenTools.defaultFontPixelHeight / 2
    property real _altRectMargin: ScreenTools.defaultFontPixelWidth / 2
    property var _controllerVehicle: missionItem.masterController.controllerVehicle
    property int _globalAltFrame: missionItem.masterController.missionController.globalAltitudeFrame
    property bool _globalAltFrameIsMixed: _globalAltFrame == QGroundControl.AltitudeFrameMixed
    property real _radius: ScreenTools.defaultFontPixelWidth / 2
    property real _fieldSpacing: ScreenTools.defaultFontPixelHeight / 2

    QGCPalette { id: qgcPal; colorGroupEnabled: root.enabled }

    /// 勾选采样点时若停留时间还是 0，用这个默认值（秒）
    readonly property real _defaultSampleHoldSeconds: 10

    /// 整条航线只允许一个采样点：找除本航点之外的已有采样点
    function _findOtherSamplePoint() {
        const items = missionItem.masterController.missionController.visualItems
        for (let i = 1; i < items.count; i++) {
            const item = items.get(i)
            if (item && item !== missionItem && item.isSimpleItem === true && item.isSamplePoint === true) {
                return item
            }
        }
        return null
    }

    function _handleSamplePointClick() {
        if (samplePointCheckBox.checked) {
            const other = _findOtherSamplePoint()
            if (other) {
                // 先回滚勾选，等用户确认；取消时旧采样点保持不变
                samplePointCheckBox.checked = false
                QGroundControl.showMessageDialog(root, qsTr("Sample Point"),
                                                 qsTr("This route already has a sample point (waypoint #%1). Move the sample point to this waypoint?").arg(other.sequenceNumber),
                                                 Dialog.Yes | Dialog.Cancel,
                                                 function() {
                                                     other.setIsSamplePoint(false, 0)
                                                     _applySamplePoint()
                                                 })
            } else {
                _applySamplePoint()
            }
        } else {
            missionItem.setIsSamplePoint(false, 0)
        }
    }

    function _applySamplePoint() {
        // 停留时间即采样点：已有值就用它，否则给个默认值，之后可在界面上改
        const holdSeconds = missionItem.holdTimeFact.value > 0 ? missionItem.holdTimeFact.value : _defaultSampleHoldSeconds
        missionItem.setIsSamplePoint(true, holdSeconds)
        samplePointCheckBox.checked = true
    }

    Connections {
        target: missionItem

        function onIsSamplePointChanged() {
            samplePointCheckBox.checked = missionItem.isSamplePoint
        }
    }

    Component.onCompleted: samplePointCheckBox.checked = missionItem.isSamplePoint

    Column {
        id: editorColumn
        anchors.margins: _margin
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: _margin

        // 采样点（仅航点）：整条航线只允许一个
        ColumnLayout {
            anchors.left:  parent.left
            anchors.right: parent.right
            spacing:       _margin
            visible:       missionItem.isSimpleItem && !missionItem.isTakeoffItem && missionItem.specifiesCoordinate

            QGCLabel {
                text:             qsTr("采样设置")
                font.bold:        true
                Layout.fillWidth: true
            }

            QGCCheckBox {
                id:               samplePointCheckBox
                text:             qsTr("到达此航点时自动采样")
                Layout.fillWidth: true
                onClicked:        _handleSamplePointClick()
            }

            // 采样停留时间（NAV_WAYPOINT 的 param1）：进任务、上传载具、飞行界面都认得
            RowLayout {
                Layout.fillWidth: true
                spacing:          ScreenTools.defaultFontPixelWidth
                visible:          samplePointCheckBox.checked

                QGCLabel { text: qsTr("Hold at sample point") }

                FactTextField {
                    fact:                  missionItem.holdTimeFact
                    showUnits:             true
                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10
                }
            }

            QGCLabel {
                Layout.fillWidth: true
                wrapMode:         Text.WordWrap
                font.pointSize:   ScreenTools.smallFontPointSize
                text:             qsTr("Only one sample point is allowed per route. Setting a new one moves it away from the current waypoint.")
                visible:          samplePointCheckBox.checked
            }
        }

        // Takeoff item
        ColumnLayout {
            anchors.margins: _margin
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: _margin
            visible: missionItem.isTakeoffItem && missionItem.wizardMode // Hack special case for takeoff item

            QGCLabel {
                text: qsTr("Move '%1' %2 to the %3 location. %4")
                    .arg(_controllerVehicle.vtol ? qsTr("T") : qsTr("T"))
                    .arg(_controllerVehicle.vtol ? qsTr("Transition Direction") : qsTr("Takeoff"))
                    .arg(_controllerVehicle.vtol ? qsTr("desired") : qsTr("climbout"))
                    .arg(_controllerVehicle.vtol ? (qsTr("Ensure distance from launch to transition direction is far enough to complete transition.")) : "")
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: !initialClickLabel.visible
            }

            QGCLabel {
                text: qsTr("Ensure clear of obstacles and into the wind.")
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: !initialClickLabel.visible
            }

            QGCButton {
                text: qsTr("Done")
                Layout.fillWidth: true
                visible: !initialClickLabel.visible
                onClicked: {
                    missionItem.wizardMode = false
                }
            }

            QGCLabel {
                id: initialClickLabel
                text: missionItem.launchTakeoffAtSameLocation ?
                                        qsTr("Click in map to set planned Takeoff location.") :
                                        qsTr("Click in map to set planned Launch location.")
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: missionItem.isTakeoffItem && !missionItem.launchCoordinate.isValid
            }
        }

        ColumnLayout {
            width: parent.width
            spacing: _fieldSpacing
            visible: !missionItem.wizardMode

            QGCTabBar {
                id: tabBar
                Layout.fillWidth: true
                visible: _multipleTabsVisible()

                property bool showBasicItems:    tabBar.visible ? tabBar.currentIndex === 0 : _basicItemsAvailable
                property bool showCameraItems:   tabBar.visible ? tabBar.currentIndex === 1 : _cameraAvailable
                property bool showAdvancedItems: tabBar.visible ? tabBar.currentIndex === 2 : _advancedItemsAvailable

                property bool _basicItemsAvailable: _specifiesAltitude || missionItem.speedSection.available || missionItem.comboboxFacts.count > 0 || missionItem.textFieldFacts.count > 0 || missionItem.nanFacts.count > 0
                property bool _advancedItemsAvailable: missionItem.comboboxFactsAdvanced.count > 0 || missionItem.textFieldFactsAdvanced.count > 0 || missionItem.nanFactsAdvanced.count > 0
                property bool _cameraAvailable: missionItem.cameraSection.available

                function _multipleTabsVisible() {
                    let visibleCount = 0
                    if (_basicItemsAvailable) visibleCount++
                    if (_cameraAvailable) visibleCount++
                    if (_advancedItemsAvailable) visibleCount++
                    return visibleCount > 1
                }

                Component.onCompleted: {
                    if (_basicItemsAvailable) {
                        tabBar.currentIndex = 0
                    } else if (_cameraAvailable) {
                        tabBar.currentIndex = 1
                    } else if (_advancedItemsAvailable) {
                        tabBar.currentIndex = 2
                    } else {
                        tabBar.currentIndex = -1
                    }
                }

                QGCTabButton {
                    id: basicItemsTab
                    icon.source: "/res/PlanSimpleItemBasic.svg"
                    visible: tabBar._basicItemsAvailable
                }

                QGCTabButton {
                    id: cameraTab
                    icon.source: "/res/PlanSimpleItemCamera.svg"
                    visible: tabBar._cameraAvailable
                }

                QGCTabButton {
                    id: advancedItemsTab
                    icon.source: "/res/PlanSimpleItemAdvanced.svg"
                    visible: tabBar._advancedItemsAvailable
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: _fieldSpacing
                visible: tabBar.showBasicItems

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: _fieldSpacing
                    visible: _specifiesAltitude

                    RowLayout {
                        Layout.fillWidth: true
                        visible: _globalAltFrameIsMixed

                        QGCLabel {
                            Layout.fillWidth: true
                            text: qsTr("Alt Frame")
                        }

                        AltFrameCombo {
                            altitudeFrame: missionItem.altitudeFrame
                            vehicle: _controllerVehicle
                            onAltitudeFrameChanged: missionItem.altitudeFrame = altitudeFrame
                        }
                    }

                    FactTextFieldSlider {
                        id: altField
                        Layout.fillWidth: true
                        label: qsTr("Altitude%1").arg(_extraLabelText())
                        fact: missionItem.altitude

                        function _extraLabelText() {
                            return qsTr(" (%1)").arg(QGroundControl.altitudeFrameExtraUnits(missionItem.altitudeFrame))
                        }
                    }

                    QGCLabel {
                        font.pointSize: ScreenTools.smallFontPointSize
                        text: qsTr("Actual AMSL alt sent: %1 %2").arg(missionItem.amslAltAboveTerrain.valueString).arg(missionItem.amslAltAboveTerrain.units)
                        visible: missionItem.altitudeFrame === QGroundControl.AltitudeFrameCalcAboveTerrain
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: _fieldSpacing

                    Repeater {
                        model: missionItem.comboboxFacts

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            QGCLabel {
                                font.pointSize: ScreenTools.smallFontPointSize
                                text: object.name
                                visible: object.name !== ""
                            }

                            FactComboBox {
                                Layout.fillWidth: true
                                indexModel: false
                                model: object.enumStrings
                                fact: object
                            }
                        }
                    }
                }

                Repeater {
                    model: missionItem.textFieldFacts

                    FactTextFieldSlider {
                        Layout.fillWidth: true
                        label: object.name
                        fact: object
                        enabled: !object.readOnly
                        warnOnUserMinMaxInvalid: false
                    }
                }

                Repeater {
                    model: missionItem.nanFacts

                    FactTextFieldSlider {
                        Layout.fillWidth: true
                        label: object.name
                        fact: object
                        showEnableCheckbox: true
                        enableCheckBoxChecked: !isNaN(object.rawValue)
                        warnOnUserMinMaxInvalid: false

                        onEnableCheckboxClicked: object.rawValue = enableCheckBoxChecked ? 0 : NaN
                    }
                }

                FactTextFieldSlider {
                    Layout.fillWidth: true
                    label: qsTr("Flight Speed")
                    fact: missionItem.speedSection.flightSpeed
                    showEnableCheckbox: true
                    enableCheckBoxChecked: missionItem.speedSection.specifyFlightSpeed
                    visible: missionItem.speedSection.available

                    onEnableCheckboxClicked: missionItem.speedSection.specifyFlightSpeed = enableCheckBoxChecked
                }
            }

            CameraSection {
                Layout.fillWidth: true
                showSectionHeader: false
                missionItem: root.missionItem
                visible: tabBar.showCameraItems

                Component.onCompleted: checked = missionItem.cameraSection.settingsSpecified
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: _fieldSpacing
                visible: tabBar.showAdvancedItems

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: _fieldSpacing

                    Repeater {
                        model: missionItem.comboboxFactsAdvanced

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            QGCLabel {
                                font.pointSize: ScreenTools.smallFontPointSize
                                text: object.name
                                visible: object.name !== ""
                            }

                            FactComboBox {
                                Layout.fillWidth: true
                                indexModel: false
                                model: object.enumStrings
                                fact: object
                            }
                        }
                    }
                }

                Repeater {
                    model: missionItem.textFieldFactsAdvanced

                    FactTextFieldSlider {
                        Layout.fillWidth: true
                        label: object.name
                        fact: object
                        enabled: !object.readOnly
                        warnOnUserMinMaxInvalid: false
                    }
                }

                Repeater {
                    model: missionItem.nanFactsAdvanced

                    FactTextFieldSlider {
                        Layout.fillWidth: true
                        label: object.name
                        fact: object
                        showEnableCheckbox: true
                        enableCheckBoxChecked: !isNaN(object.rawValue)
                        warnOnUserMinMaxInvalid: false

                        onEnableCheckboxClicked: object.rawValue = enableCheckBoxChecked ? 0 : NaN
                    }
                }
            }
        }
    }
}
