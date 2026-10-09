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
    property var _maxVolumeFact: factPanelController.getParameterFact(-1, "WS_MAX_VOLUME", false)

    QGCPalette { id: qgcPal; colorGroupEnabled: root.enabled }

    FactPanelController { id: factPanelController }

    function _findOtherSamplePoint() {
        // 整条航线只允许一个采样点：遍历任务里除当前航点外的其它航点，找已勾选采样的
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
            // 勾选采样：先查任务里是否已有其它采样点，有则提示并征得同意后移过来
            const other = _findOtherSamplePoint()
            if (other) {
                samplePointCheckBox.checked = false
                QGroundControl.showMessageDialog(root, qsTr("Sample Point"),
                                                 qsTr("任务中已有采样点（航点 #%1）。是否将采样点移动到当前航点？").arg(other.missionItemNumber > 0 ? other.missionItemNumber : other.sequenceNumber),
                                                 Dialog.Yes | Dialog.Cancel,
                                                 function() {
                                                     other.setIsSamplePoint(false, 0)
                                                     missionItem.setIsSamplePoint(true, 0)
                                                 })
            } else {
                missionItem.setIsSamplePoint(true, 0)
            }
        } else {
            // 取消勾选
            missionItem.setIsSamplePoint(false, 0)
        }
    }

    function _selectSampleBottle(bottle) {
        missionItem.sampleBottle = bottle
        if (samplePointCheckBox.checked) {
            missionItem.autoSampleEnabled = true
        }
    }

    function _selectSampleCapacity(capacityMl) {
        missionItem.sampleCapacityMl = capacityMl
        if (samplePointCheckBox.checked) {
            missionItem.autoSampleEnabled = true
        }
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

        // 采样点（仅航点）：整条航线只允许一个，显示在“采样”页签里

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

                property bool showSamplingItems:  tabBar.visible ? samplingTab.checked     : _samplingAvailable
                property bool showBasicItems:     tabBar.visible ? basicItemsTab.checked   : _basicItemsAvailable
                property bool showCameraItems:    tabBar.visible ? cameraTab.checked       : _cameraAvailable
                property bool showAdvancedItems:  tabBar.visible ? advancedItemsTab.checked : _advancedItemsAvailable

                property bool _samplingAvailable: missionItem.isSimpleItem && !missionItem.isTakeoffItem && missionItem.specifiesCoordinate
                property bool _basicItemsAvailable: missionItem.comboboxFacts.count > 0
                                                    || missionItem.textFieldFacts.count > 0
                                                    || missionItem.nanFacts.count > 0
                property bool _advancedItemsAvailable: missionItem.comboboxFactsAdvanced.count > 0 || missionItem.textFieldFactsAdvanced.count > 0 || missionItem.nanFactsAdvanced.count > 0
                property bool _cameraAvailable: missionItem.cameraSection.available

                function _multipleTabsVisible() {
                    let visibleCount = 0
                    if (_samplingAvailable) visibleCount++
                    if (_basicItemsAvailable) visibleCount++
                    if (_cameraAvailable) visibleCount++
                    if (_advancedItemsAvailable) visibleCount++
                    return visibleCount > 1
                }

                // 默认点开航点就落在“采样”页
                Component.onCompleted: {
                    if (_samplingAvailable) {
                        samplingTab.checked = true
                    } else if (_basicItemsAvailable) {
                        basicItemsTab.checked = true
                    } else if (_cameraAvailable) {
                        cameraTab.checked = true
                    } else if (_advancedItemsAvailable) {
                        advancedItemsTab.checked = true
                    } else {
                        tabBar.currentIndex = -1
                    }
                }

                QGCTabButton {
                    id: basicItemsTab
                    icon.source: "/res/PlanSimpleItemBasic.svg"
                    visible: tabBar._basicItemsAvailable
                }

                // 采样设置页：相机左边，默认页
                QGCTabButton {
                    id: samplingTab
                    icon.source: "/qmlimages/WaterSamplingIcon.svg"
                    visible: tabBar._samplingAvailable
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

            // ── 采样设置页内容（默认页）──
            ColumnLayout {
                Layout.fillWidth: true
                spacing: _fieldSpacing
                visible: tabBar.showSamplingItems

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

                QGCLabel {
                    Layout.fillWidth: true
                    text:             qsTr("选择采样瓶")
                    visible:          samplePointCheckBox.checked
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns:          4
                    rowSpacing:       ScreenTools.defaultFontPixelWidth * 0.5
                    columnSpacing:    ScreenTools.defaultFontPixelWidth * 0.5
                    visible:          samplePointCheckBox.checked

                    Repeater {
                        model: [1, 2, 3, 4, 5, 6, 7, 8]

                        QGCButton {
                            required property int modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 2.4
                            text: qsTr("瓶%1").arg(modelData)
                            checkable: true
                            checked: missionItem.sampleBottle === modelData
                            onClicked: root._selectSampleBottle(modelData)
                        }
                    }
                }

                QGCLabel {
                    Layout.fillWidth: true
                    text:             qsTr("选择容量")
                    visible:          samplePointCheckBox.checked && missionItem.sampleBottle > 0
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing:          ScreenTools.defaultFontPixelWidth * 0.5
                    visible:          samplePointCheckBox.checked && missionItem.sampleBottle > 0

                    Repeater {
                        model: [
                            { ml: 500, label: "500ml" },
                            { ml: 1000, label: "1000ml" },
                            { ml: 2500, label: "2500ml" },
                            { ml: 5000, label: "5000ml" }
                        ]

                        QGCButton {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 6
                            Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 2.4
                            text: modelData.label
                            checkable: true
                            checked: missionItem.sampleCapacityMl === modelData.ml
                            enabled: root._maxVolumeFact !== null
                                     && modelData.ml <= Number(root._maxVolumeFact.value)
                            onClicked: root._selectSampleCapacity(modelData.ml)
                        }
                    }
                }

                QGCLabel {
                    Layout.fillWidth: true
                    visible:          samplePointCheckBox.checked && missionItem.autoSampleEnabled
                                     && missionItem.sampleBottle > 0 && missionItem.sampleBottle <= 2
                                     && missionItem.sampleCapacityMl > 0
                    text:             qsTr("预计采样时长：%1秒").arg(Math.ceil(missionItem.sampleDurationSeconds))
                    font.pointSize:   ScreenTools.smallFontPointSize
                }

                QGCLabel {
                    Layout.fillWidth: true
                    visible:          samplePointCheckBox.checked && missionItem.sampleBottle > 2
                    wrapMode:         Text.WordWrap
                    font.pointSize:   ScreenTools.smallFontPointSize
                    text:             qsTr("瓶3至瓶8仅供界面选择，当前飞控自动采样只支持瓶1和瓶2。")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: _fieldSpacing
                visible: tabBar.showBasicItems

                // 无人船用不到高度：整个高度输入区隐藏
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: _fieldSpacing
                    visible: false

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
