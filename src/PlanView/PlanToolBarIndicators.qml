import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FactControls

// Toolbar for Plan View
RowLayout {
    required property var planMasterController
    property bool showRallyPointsHelp: false

    signal toolbarButtonClicked()

    id: root
    spacing: ScreenTools.defaultFontPixelWidth

    property var _planMasterController: planMasterController
    property var _missionController: _planMasterController.missionController
    property var _geoFenceController: _planMasterController.geoFenceController
    property var _rallyPointController: _planMasterController.rallyPointController
    property bool _controllerOffline: _planMasterController.offline
    property var _saveDirty: _planMasterController.dirtyForSave
    property var _uploadDirty: _planMasterController.dirtyForUpload
    property var _syncInProgress: _planMasterController.syncInProgress
    property var _visualItems: _missionController.visualItems
    property bool _hasPlanItems: _planMasterController.containsItems

    readonly property real _margins: ScreenTools.defaultFontPixelWidth

    function _uploadClicked() {
        _planMasterController.upload()
    }

    function _downloadClicked() {
        if (_saveDirty) {
            QGroundControl.showMessageDialog(root, qsTr("Download"),
                                         qsTr("You have unsaved changes. Downloading from the Vehicle will lose these changes. Are you sure?"),
                                         Dialog.Yes | Dialog.Cancel,
                                         function() { _planMasterController.loadFromVehicle() })
        } else {
            _planMasterController.loadFromVehicle()
        }
    }

    function _openButtonClicked() {
        if (_saveDirty || _uploadDirty) {
            QGroundControl.showMessageDialog(root, qsTr("Open Plan"),
                                        qsTr("You have unsaved/unsent changes. Loading a new Plan will lose these changes. Are you sure?"),
                                        Dialog.Yes | Dialog.Cancel,
                                        function() { _planMasterController.loadFromSelectedFile() } )
        } else {
            _planMasterController.loadFromSelectedFile()
        }
    }

    function _saveButtonClicked() {
        if (_planMasterController.currentPlanFileName === "") {
            if (_planMasterController.currentPlanFile === "") {
                // No file and no name typed — open the file dialog
                _planMasterController.saveToSelectedFile()
            } else {
                // Have a file but name was cleared — save to the existing file
                _planMasterController.saveToCurrent()
            }
            return
        }

        if (_planMasterController.currentPlanFile === "" || _planMasterController.planFileRenamed) {
            // First save with a typed name, or name was changed since last save
            let fullName = _planMasterController.currentPlanFileName + "." + _planMasterController.fileExtension
            let msg = _planMasterController.resolvedPlanFileExists()
                ? qsTr("'%1' already exists. Overwrite?").arg(fullName)
                : qsTr("Save as '%1'?").arg(fullName)
            QGroundControl.showMessageDialog(root, qsTr("Save"), msg,
                Dialog.Yes | Dialog.No,
                function() { _planMasterController.saveWithCurrentName() })
        } else {
            _planMasterController.saveToCurrent()
        }
    }

    function _saveAsKMLClicked() {
        // Don't save if we only have Mission Settings item
        if (_visualItems.count > 1) {
            _planMasterController.saveKmlToSelectedFile()
        }
    }

    function _storageClearButtonClicked() {
        QGroundControl.showMessageDialog(root, qsTr("Clear"),
                                     qsTr("Are you sure you want to remove all the items from the plan editor?"),
                                     Dialog.Yes | Dialog.Cancel,
                                     function() { _planMasterController.removeAll(); })
    }

    function _vehicleClearButtonClicked() {
        QGroundControl.showMessageDialog(root, qsTr("Clear"),
                                     qsTr("Are you sure you want to remove the plan from the vehicle and the plan editor?"),
                                     Dialog.Yes | Dialog.Cancel,
                                     function() {
                                        _planMasterController.removeAllFromVehicle()
                                     })
    }

    function _clearClicked() {
        if (_planMasterController.offline) {
            _storageClearButtonClicked();
        } else {
            _vehicleClearButtonClicked();
        }
    }

    QGCPalette { id: qgcPal }

    QGCButton {
        objectName: "planToolbar_openButton"
        text: qsTr("Open")
        iconSource: "/qmlimages/Plan.svg"
        enabled: !_planMasterController.syncInProgress
        onClicked: { toolbarButtonClicked(); _openButtonClicked() }
    }

    QGCButton {
        objectName: "planToolbar_saveButton"
        text: qsTr("Save")
        iconSource: "/res/SaveToDisk.svg"
        enabled: !_syncInProgress && _hasPlanItems
        primary: _saveDirty
        onClicked: { toolbarButtonClicked(); _saveButtonClicked() }
    }

    QGCButton {
        id: uploadButton
        objectName: "planToolbar_uploadButton"
        text: qsTr("Upload")
        iconSource: "/res/UploadToVehicle.svg"
        enabled: !_syncInProgress && _hasPlanItems && !_controllerOffline
        visible: !_syncInProgress
        primary: _uploadDirty && !_controllerOffline
        onClicked: { toolbarButtonClicked(); _uploadClicked() }
    }

    QGCButton {
        objectName: "planToolbar_clearButton"
        text: qsTr("Clear")
        iconSource: "/res/TrashCan.svg"
        enabled: !_syncInProgress
        onClicked: { toolbarButtonClicked(); _clearClicked() }
    }

    QGCButton {
        iconSource: "qrc:/qmlimages/Hamburger.svg"

        onClicked: {
            let position = Qt.point(width, height / 2)
            // For some strange reason using mainWindow in mapToItem doesn't work, so we use globals.parent instead which also gets us mainWindow
            position = mapToItem(globals.parent, position)
            var dropPanel = hamburgerDropPanelComponent.createObject(mainWindow, { clickRect: Qt.rect(position.x, position.y, 0, 0) })
            // 关掉就销毁：面板是模态的，且里面可能留着“无效值”的输入框。
            // 以前只是 close() 不销毁，面板会一直被 mainWindow 持有：既可能残留模态遮挡，
            // 又把校验错误计数留在那里减不回去，导致之后切界面、加航点全被拦住。
            dropPanel.closed.connect(function() { dropPanel.destroy() })
            dropPanel.open()
        }
    }

    QGCLabel {
        text:    qsTr("Click in map to add rally points")
        visible: root.showRallyPointsHelp
        Layout.alignment: Qt.AlignVCenter
    }

    Component {
        id: hamburgerDropPanelComponent

        DropPanel {
            id: dropPanel

            sourceComponent: Component {
                ColumnLayout {
                    spacing: ScreenTools.defaultFontPixelHeight / 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing:         ScreenTools.defaultFontPixelWidth

                        QGCLabel {
                            text:             qsTr("Mission Loops")
                            Layout.alignment: Qt.AlignVCenter
                        }

                        FactTextField {
                            fact:                   _visualItems.count > 0 ? _visualItems.get(0).loopCount : null
                            showUnits:              false
                            Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 5
                            Layout.alignment:       Qt.AlignVCenter
                        }

                        // 循环跑完回 HOME 点：勾选后上传的任务末尾会带一条 RTL（排在 DO_JUMP 之后）
                        QGCCheckBox {
                            text:               qsTr("循环完返回HOME点")
                            visible:            _visualItems.count > 0
                            checked:            _visualItems.count > 0 ? _visualItems.get(0).returnHomeAfterLoop.rawValue : false
                            Layout.alignment:   Qt.AlignVCenter

                            onClicked: {
                                if (_visualItems.count > 0) {
                                    _visualItems.get(0).returnHomeAfterLoop.rawValue = checked
                                }
                            }
                        }
                    }

                    QGCButton {
                        Layout.fillWidth: true
                        text:    qsTr("Save Mission to History")
                        enabled: !_syncInProgress && _hasPlanItems

                        onClicked: {
                            dropPanel.close()
                            missionNameDialogFactory.open()
                        }
                    }

                    QGCButton {
                        Layout.fillWidth: true
                        text: qsTr("Open Mission History")

                        onClicked: {
                            dropPanel.close()
                            historyDialogFactory.open()
                        }
                    }

                    QGCButton {
                        Layout.fillWidth: true
                        text: qsTr("Save as KML")
                        enabled: !_syncInProgress && _hasPlanItems

                        onClicked: {
                            dropPanel.close()
                            _saveAsKMLClicked()
                        }
                    }

                    QGCButton {
                        Layout.fillWidth: true
                        text: qsTr("Download")
                        enabled: !_syncInProgress && !_controllerOffline
                        visible: !_syncInProgress

                        onClicked: {
                            dropPanel.close()
                            _downloadClicked()
                        }
                    }
                }
            }
        }
    }

    /// 保存当前任务：输入任务名，存为历史目录下的 .plan 快照
    QGCPopupDialogFactory {
        id: missionNameDialogFactory

        dialogComponent: Component {
            QGCPopupDialog {
                id:      missionNameDialog
                title:   qsTr("Save Mission to History")
                buttons: Dialog.Ok | Dialog.Cancel

                ColumnLayout {
                    spacing: ScreenTools.defaultFontPixelHeight / 2

                    QGCLabel {
                        text: qsTr("Mission name (empty uses timestamp only)")
                    }

                    QGCTextField {
                        id:                    missionNameField
                        Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 30
                        placeholderText:       qsTr("Mission name")

                        Component.onCompleted: forceActiveFocus()
                    }
                }

                onAccepted: {
                    if (MissionHistoryManager.saveCurrentPlan(_planMasterController, missionNameField.text)) {
                        QGroundControl.showMessageDialog(missionNameDialog, qsTr("Save Mission to History"), qsTr("Saved to mission history"))
                    }
                }
            }
        }
    }

    /// 打开历史任务：名称 + 保存时间两列，行尾载入/删除，底部清空
    QGCPopupDialogFactory {
        id: historyDialogFactory

        dialogComponent: Component {
            QGCPopupDialog {
                id:      historyDialog
                title:   qsTr("Open Mission History")
                buttons: Dialog.Cancel

                ListModel { id: historyModel }

                function _refreshHistory() {
                    historyModel.clear()
                    const entries = MissionHistoryManager.historyList
                    for (let i = 0; i < entries.length; i++) {
                        historyModel.append({ name: entries[i].name, time: entries[i].time, size: entries[i].size })
                    }
                }

                /// 未保存/未发送的改动会被载入覆盖，先确认
                function _loadEntry(index) {
                    if (_saveDirty || _uploadDirty) {
                        QGroundControl.showMessageDialog(historyDialog, qsTr("Open Plan"),
                                                         qsTr("You have unsaved/unsent changes. Loading a new Plan will lose these changes. Are you sure?"),
                                                         Dialog.Yes | Dialog.Cancel,
                                                         function() { _doLoad(index) })
                    } else {
                        _doLoad(index)
                    }
                }

                function _doLoad(index) {
                    if (MissionHistoryManager.loadHistory(_planMasterController, index)) {
                        historyDialog.close()
                    }
                }

                ColumnLayout {
                    spacing: ScreenTools.defaultFontPixelHeight / 2

                    QGCLabel {
                        text: qsTr("%1 saved missions").arg(historyListView.count)
                    }

                    QGCLabel {
                        text:    qsTr("No saved missions")
                        visible: historyListView.count === 0
                    }

                    QGCListView {
                        id:                      historyListView
                        Layout.preferredWidth:   ScreenTools.defaultFontPixelWidth * 58
                        Layout.preferredHeight:  Math.max(ScreenTools.defaultFontPixelHeight * 4,
                                                          Math.min(contentHeight, ScreenTools.defaultFontPixelHeight * 16))
                        model:                   historyModel

                        delegate: Rectangle {
                            // 视图的 index 与 MissionHistoryManager.historyList 的下标一致
                            required property int    index
                            required property string name
                            required property string time
                            required property string size

                            width:  historyListView.width
                            height: historyRow.implicitHeight + ScreenTools.defaultFontPixelHeight / 2
                            color:  qgcPal.window

                            RowLayout {
                                id:                     historyRow
                                anchors.left:           parent.left
                                anchors.right:          parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins:        ScreenTools.defaultFontPixelWidth / 2
                                spacing:                ScreenTools.defaultFontPixelWidth

                                QGCLabel {
                                    Layout.fillWidth: true
                                    Layout.maximumWidth: ScreenTools.defaultFontPixelWidth * 20
                                    text:             name
                                    elide:            Text.ElideMiddle
                                }

                                QGCLabel {
                                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 16
                                    text:                  time
                                }

                                QGCLabel {
                                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 8
                                    horizontalAlignment:   Text.AlignRight
                                    text:                  size
                                }

                                QGCButton {
                                    text: qsTr("Load")

                                    onClicked: historyDialog._loadEntry(index)
                                }

                                QGCButton {
                                    text: qsTr("Delete")

                                    onClicked: {
                                        if (MissionHistoryManager.deleteHistory(index)) {
                                            historyDialog._refreshHistory()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    QGCButton {
                        Layout.fillWidth: true
                        text:    qsTr("Clear All")
                        enabled: historyListView.count > 0

                        onClicked: {
                            MissionHistoryManager.clearHistory()
                            historyDialog._refreshHistory()
                        }
                    }
                }

                Component.onCompleted: _refreshHistory()
            }
        }
    }
}
