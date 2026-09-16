import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// Map provider, type, and elevation provider selection.
/// Wraps a SettingsGroupLayout with cascading comboboxes driven by QGCMapEngineManager.
SettingsGroupLayout {
    Layout.fillWidth: true

    property var _mapEngineManager:     QGroundControl.mapEngineManager
    property Fact _mapProviderFact:     QGroundControl.settingsManager.flightMapSettings.mapProvider
    property Fact _mapTypeFact:         QGroundControl.settingsManager.flightMapSettings.mapType
    property Fact _elevationProviderFact: QGroundControl.settingsManager.flightMapSettings.elevationMapProvider

    // Map provider, map type and elevation provider names are never translated in C++: they are the
    // identity used by the settings, the tile cache and the offline tile set database. The combos
    // below therefore display a translated label while still storing the untranslated name. Names
    // without a label (e.g. a provider added in C++ without a label here) fall back to the name.
    readonly property var _providerLabels: ({
        "Bing":          qsTr("Bing"),
        "Custom":        qsTr("Custom"),
        "Eniro":         qsTr("Eniro"),
        "Esri":          qsTr("Esri"),
        "Google":        qsTr("Google"),
        "Japan":         qsTr("Japan"),
        "LINZ":          qsTr("LINZ"),
        "Mapbox":        qsTr("Mapbox"),
        "MapQuest":      qsTr("MapQuest"),
        "OpenAIP":       qsTr("OpenAIP"),
        "OpenStreetMap": qsTr("OpenStreetMap"),
        "Statkart":      qsTr("Statkart"),
        "Svalbard":      qsTr("Svalbard"),
        "TianDiTu":      qsTr("Tianditu"),
        "Tianditu":      qsTr("Tianditu"),
        "VWorld":        qsTr("VWorld")
    })

    readonly property var _mapTypeLabels: ({
        "Aviation Map":         qsTr("Aviation Map"),
        "Base Map":             qsTr("Base Map"),
        "Basic Streets":        qsTr("Basic Streets"),
        "Bright":               qsTr("Bright"),
        "Custom":               qsTr("Custom"),
        "Dark":                 qsTr("Dark"),
        "GSI Anaglyph":         qsTr("GSI Anaglyph"),
        "GSI Contours":         qsTr("GSI Contours"),
        "GSI Relief Map":       qsTr("GSI Relief Map"),
        "GSI Seamless Imagery": qsTr("GSI Seamless Imagery"),
        "GSI Slope Map":        qsTr("GSI Slope Map"),
        "Hybrid Map":           qsTr("Hybrid Map"),
        "Labels":               qsTr("Labels"),
        "Light":                qsTr("Light"),
        "Outdoors":             qsTr("Outdoors"),
        "Road Map":             qsTr("Road Map"),
        "Satellite Map":        qsTr("Satellite Map"),
        "Terrain Map":          qsTr("Terrain Map"),
        "URL":                  qsTr("URL"),
        "World Satellite Map":  qsTr("World Satellite Map"),
        "World Street Map":     qsTr("World Street Map")
    })

    readonly property var _elevationProviderLabels: ({
        "Copernicus Terrain": qsTr("Copernicus Terrain")
    })

    function _label(table, name) {
        const label = table[name]
        return label === undefined ? name : label
    }

    LabelledComboBox {
        label: qsTr("Map Provider")
        model: _mapEngineManager.mapProviderList.map(function (name) { return _label(_providerLabels, name) })

        onActivated: (index) => {
            const provider = _mapEngineManager.mapProviderList[index]
            _mapProviderFact.rawValue = provider
            _mapTypeFact.rawValue = _mapEngineManager.mapTypeList(provider)[0]
        }

        Component.onCompleted: {
            const index = _mapEngineManager.mapProviderList.indexOf(_mapProviderFact.rawValue)
            comboBox.currentIndex = index < 0 ? 0 : index
        }
    }

    LabelledComboBox {
        label: qsTr("Map Type")
        model: _mapEngineManager.mapTypeList(_mapProviderFact.rawValue).map(function (name) { return _label(_mapTypeLabels, name) })

        onActivated: (index) => {
            _mapTypeFact.rawValue = _mapEngineManager.mapTypeList(_mapProviderFact.rawValue)[index]
        }

        Component.onCompleted: {
            const index = _mapEngineManager.mapTypeList(_mapProviderFact.rawValue).indexOf(_mapTypeFact.rawValue)
            comboBox.currentIndex = index < 0 ? 0 : index
        }
    }

    LabelledComboBox {
        label: qsTr("Elevation Provider")
        model: _mapEngineManager.elevationProviderList.map(function (name) { return _label(_elevationProviderLabels, name) })

        onActivated: (index) => {
            _elevationProviderFact.rawValue = _mapEngineManager.elevationProviderList[index]
        }

        Component.onCompleted: {
            const index = _mapEngineManager.elevationProviderList.indexOf(_elevationProviderFact.rawValue)
            comboBox.currentIndex = index < 0 ? 0 : index
        }
    }
}
