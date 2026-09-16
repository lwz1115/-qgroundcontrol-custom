#pragma once

#include "MapProvider.h"

class CustomURLMapProvider : public MapProvider
{
public:
    CustomURLMapProvider()
        : MapProvider(
            QObject::tr("Custom URL"),
            QStringLiteral(""),
            QStringLiteral(""),
            QGC_AVERAGE_TILE_SIZE,
            MapProvider::CustomMap) {}

private:
    QString _getURL(int x, int y, int zoom) const final;
};

class CyberJapanMapProvider : public MapProvider
{
protected:
    CyberJapanMapProvider(const QString &mapName, const QString &mapTypeId, const QString &imageFormat)
        : MapProvider(
            mapName,
            QStringLiteral("https://cyberjapandata.gsi.go.jp/xyz/std"),
            imageFormat,
            QGC_AVERAGE_TILE_SIZE,
            MapProvider::StreetMap)
        , _mapTypeId(mapTypeId) {}

private:
    QString _getURL(int x, int y, int zoom) const final;

    const QString _mapTypeId;
    const QString _mapUrl = QStringLiteral("https://cyberjapandata.gsi.go.jp/xyz/%1/%2/%3/%4.%5");
};

class JapanStdMapProvider : public CyberJapanMapProvider
{
public:
    JapanStdMapProvider()
        : CyberJapanMapProvider(
            QObject::tr("Japan GSI Contours"),
            QStringLiteral("std"),
            QStringLiteral("png")) {}
};

class JapanSeamlessMapProvider : public CyberJapanMapProvider
{
public:
    JapanSeamlessMapProvider()
        : CyberJapanMapProvider(
            QObject::tr("Japan GSI Seamless Imagery"),
            QStringLiteral("seamlessphoto"),
            QStringLiteral("jpg")) {}
};

class JapanAnaglyphMapProvider : public CyberJapanMapProvider
{
public:
    JapanAnaglyphMapProvider()
        : CyberJapanMapProvider(
            QObject::tr("Japan GSI Anaglyph"),
            QStringLiteral("anaglyphmap_color"),
            QStringLiteral("png")) {}
};

class JapanSlopeMapProvider : public CyberJapanMapProvider
{
public:
    JapanSlopeMapProvider()
        : CyberJapanMapProvider(
            QObject::tr("Japan GSI Slope Map"),
            QStringLiteral("slopemap"),
            QStringLiteral("png")) {}
};

class JapanReliefMapProvider : public CyberJapanMapProvider
{
public:
    JapanReliefMapProvider()
        : CyberJapanMapProvider(
            QObject::tr("Japan GSI Relief Map"),
            QStringLiteral("relief"),
            QStringLiteral("png")) {}
};

class LINZBasemapMapProvider : public MapProvider
{
public:
    LINZBasemapMapProvider()
        : MapProvider(
            QObject::tr("LINZ Base Map"),
            QStringLiteral("https://basemaps.linz.govt.nz/v1/tiles/aerial"),
            QStringLiteral("png"),
            QGC_AVERAGE_TILE_SIZE,
            MapProvider::SatelliteMapDay) {}

private:
    QString _getURL(int x, int y, int zoom) const final;

    const QString _mapUrl = QStringLiteral("https://basemaps.linz.govt.nz/v1/tiles/aerial/EPSG:3857/%1/%2/%3.%4?api=d01ev80nqcjxddfvc6amyvkk1ka");
};

class OpenAIPMapProvider : public MapProvider
{
public:
    OpenAIPMapProvider()
        : MapProvider(
            QObject::tr("OpenAIP Aviation Map"),
            QStringLiteral("https://www.openaip.net"),
            QStringLiteral("png"),
            QGC_AVERAGE_TILE_SIZE,
            MapProvider::CustomMap) {}

private:
    QString _getURL(int x, int y, int zoom) const final;

    const QString _mapUrl = QStringLiteral("https://api.tiles.openaip.net/api/data/openaip/%1/%2/%3.png");
};

class OpenStreetMapProvider : public MapProvider
{
public:
    OpenStreetMapProvider()
        : MapProvider(
            QObject::tr("OpenStreetMap Road Map"),
            QStringLiteral("https://www.openstreetmap.org"),
            QStringLiteral("png"),
            QGC_AVERAGE_TILE_SIZE,
            MapProvider::StreetMap) {}

private:
    QString _getURL(int x, int y, int zoom) const final;

    const QString _mapUrl = QStringLiteral("http://tile.openstreetmap.org/%1/%2/%3.png");
};

class StatkartMapProvider : public MapProvider
{
protected:
    StatkartMapProvider(const QString &mapName, const QString &mapTypeId)
        : MapProvider(
            mapName,
            QStringLiteral("https://norgeskart.no/"),
            QStringLiteral("png"),
            QGC_AVERAGE_TILE_SIZE,
            MapProvider::StreetMap)
        , _mapTypeId(mapName) {}

private:
    QString _getURL(int x, int y, int zoom) const final;

    const QString _mapTypeId;
    const QString _mapUrl = QStringLiteral("https://cache.kartverket.no/v1/wmts/1.0.0/topo/default/webmercator/%1/%2/%3.png");
};

class StatkartTopoMapProvider : public StatkartMapProvider
{
public:
    StatkartTopoMapProvider()
        : StatkartMapProvider(
            QObject::tr("Statkart Terrain Map"),
            QStringLiteral("topo4")) {}
};

class StatkartBaseMapProvider : public StatkartMapProvider
{
public:
    StatkartBaseMapProvider()
        : StatkartMapProvider(
            QObject::tr("Statkart Base Map"),
            QStringLiteral("norgeskart_bakgrunn")) {}
};

class SvalbardMapProvider : public MapProvider
{
public:
    SvalbardMapProvider()
        : MapProvider(
            QObject::tr("Svalbard Terrain Map"),
            QStringLiteral("https://www.npolar.no/"),
            QStringLiteral("png"),
            QGC_AVERAGE_TILE_SIZE,
            MapProvider::StreetMap) {}

private:
    QString _getURL(int x, int y, int zoom) const final;

    const QString _mapUrl = QStringLiteral("https://geodata.npolar.no/arcgis/rest/services/Basisdata/NP_Basiskart_Svalbard_WMTS_3857/MapServer/WMTS/tile/1.0.0/Basisdata_NP_Basiskart_Svalbard_WMTS_3857/default/default028mm/%1/%2/%3");
};


class EniroMapProvider : public MapProvider
{
public:
    EniroMapProvider()
        : MapProvider(
            QObject::tr("Eniro Terrain Map"),
            QStringLiteral("https://www.eniro.se/"),
            QStringLiteral("png"),
            QGC_AVERAGE_TILE_SIZE,
            MapProvider::StreetMap) {}

private:
    QString _getURL(int x, int y, int zoom) const final;

    const QString _mapUrl = QStringLiteral("http://map.eniro.com/geowebcache/service/tms1.0.0/map/%1/%2/%3.%4");
};

class MapQuestMapProvider : public MapProvider
{
protected:
    MapQuestMapProvider(const QString &mapName, const QString &mapTypeId, MapProvider::MapStyle mapType)
        : MapProvider(
            mapName,
            QStringLiteral("https://mapquest.com"),
            QStringLiteral("jpg"),
            QGC_AVERAGE_TILE_SIZE,
            mapType)
        , _mapTypeId(mapTypeId) {}

private:
    QString _getURL(int x, int y, int zoom) const final;

    const QString _mapTypeId;
    const QString _mapUrl = QStringLiteral("http://otile%1.mqcdn.com/tiles/1.0.0/%2/%3/%4/%5.%6");
};

class MapQuestMapMapProvider : public MapQuestMapProvider
{
public:
    MapQuestMapMapProvider()
        : MapQuestMapProvider(
            QObject::tr("MapQuest Road Map"),
            QStringLiteral("map"),
            MapProvider::StreetMap) {}
};

class MapQuestSatMapProvider : public MapQuestMapProvider
{
public:
    MapQuestSatMapProvider()
        : MapQuestMapProvider(
            QObject::tr("MapQuest Satellite Map"),
            QStringLiteral("sat"),
            MapProvider::SatelliteMapDay) {}
};

class VWorldMapProvider : public MapProvider
{
protected:
    VWorldMapProvider(const QString &mapName, const QString &mapTypeId, const QString &imageFormat, quint32 averageSize, MapProvider::MapStyle mapStyle)
        : MapProvider(
            mapName,
            QStringLiteral("www.vworld.kr"),
            imageFormat,
            averageSize,
            mapStyle)
        , _mapTypeId(mapTypeId) {}

private:
    QString _getURL(int x, int y, int zoom) const final;

    const QString _mapTypeId;
    const QString _mapUrl = QStringLiteral("http://api.vworld.kr/req/wmts/1.0.0/%1/%2/%3/%4/%5.%6");
};

class VWorldStreetMapProvider : public VWorldMapProvider
{
public:
    VWorldStreetMapProvider()
        : VWorldMapProvider(
            QObject::tr("VWorld Road Map"),
            QStringLiteral("Base"),
            QStringLiteral("png"),
            QGC_AVERAGE_TILE_SIZE,
            MapProvider::StreetMap) {}
};

class VWorldSatMapProvider : public VWorldMapProvider
{
public:
    VWorldSatMapProvider()
        : VWorldMapProvider(
            QObject::tr("VWorld Satellite Map"),
            QStringLiteral("Satellite"),
            QStringLiteral("jpeg"),
            QGC_AVERAGE_TILE_SIZE,
            MapProvider::SatelliteMapDay) {}
};
