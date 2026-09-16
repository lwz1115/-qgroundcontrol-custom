#pragma once

#include "MapProvider.h"

class EsriMapProvider : public MapProvider
{
protected:
    EsriMapProvider(const QString &mapName, const QString &mapTypeId, quint32 averageSize, MapProvider::MapStyle mapType)
        : MapProvider(
            mapName,
            QStringLiteral(""),
            QStringLiteral(""),
            averageSize,
            mapType)
        , _mapTypeId(mapTypeId) {}

public:
    QByteArray getToken() const final;

private:
    QString _getURL(int x, int y, int zoom) const final;

    const QString _mapTypeId;
    const QString _mapUrl = QStringLiteral("http://services.arcgisonline.com/ArcGIS/rest/services/%1/MapServer/tile/%2/%3/%4");
};

class EsriWorldStreetMapProvider : public EsriMapProvider
{
public:
    EsriWorldStreetMapProvider()
        : EsriMapProvider(
            QObject::tr("Esri World Street Map"),
            QStringLiteral("World_Street_Map"),
            QGC_AVERAGE_TILE_SIZE,
            MapProvider::StreetMap) {}
};

class EsriWorldSatelliteMapProvider : public EsriMapProvider
{
public:
    EsriWorldSatelliteMapProvider()
        : EsriMapProvider(
            QObject::tr("Esri World Satellite Map"),
            QStringLiteral("World_Imagery"),
            QGC_AVERAGE_TILE_SIZE,
            MapProvider::SatelliteMapDay) {}
};

class EsriTerrainMapProvider : public EsriMapProvider
{
public:
    EsriTerrainMapProvider()
        : EsriMapProvider(
            QObject::tr("Esri Terrain Map"),
            QStringLiteral("World_Terrain_Base"),
            QGC_AVERAGE_TILE_SIZE,
            MapProvider::TerrainMap) {}
};
