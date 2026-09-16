#include "FlightMapSettings.h"

#include <QtCore/QSettings>

DECLARE_SETTINGGROUP(FlightMap, "FlightMap")
{
    // The Copernicus elevation provider was renamed; a stored legacy name no longer resolves
    // to a registered provider.
    const QString elevationMapProviderKey = QStringLiteral("elevationMapProvider");
    QSettings settings;
    settings.beginGroup(_name);
    if (settings.value(elevationMapProviderKey).toString() == QStringLiteral("Copernicus")) {
        settings.setValue(elevationMapProviderKey, QStringLiteral("Copernicus Terrain"));
    }
    settings.endGroup();
}

DECLARE_SETTINGSFACT(FlightMapSettings, mapProvider)
DECLARE_SETTINGSFACT(FlightMapSettings, mapType)
DECLARE_SETTINGSFACT(FlightMapSettings, elevationMapProvider)
