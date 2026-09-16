#pragma once

#include "MapProvider.h"

static constexpr const quint32 AVERAGE_BING_STREET_MAP = 1297;
static constexpr const quint32 AVERAGE_BING_SAT_MAP    = 19597;

class BingMapProvider : public MapProvider
{
protected:
    BingMapProvider(const QString &mapName, const QString &mapTypeCode, const QString &imageFormat, quint32 averageSize,
                    MapProvider::MapStyle mapType)
        : MapProvider(mapName, QStringLiteral("https://www.bing.com/maps/"), imageFormat, averageSize, mapType)
        , _mapTypeId(mapTypeCode) {}

public:
    bool isBingProvider() const final { return true; }

private:
    QString _getURL(int x, int y, int zoom) const final;

    const QString _mapTypeId;
    // https, not http: the cleartext endpoint fails about half of all tile requests with 502.
    // Bing serves its current imagery for any accepted version value; 1 is the documented
    // "latest" form, while the old pin (2981) is a legacy version Microsoft can retire.
    const QString _mapUrl = QStringLiteral("https://ecn.t%1.tiles.virtualearth.net/tiles/%2%3.%4?g=%5&mkt=%6");
    const QString _versionBingMaps = QStringLiteral("1");

    /*QUrl m_url;
    const QString m_scheme = QStringLiteral("http");
    const QString m_host = QStringLiteral("ecn.t%1.tiles.virtualearth.net");
    const QString m_path = QStringLiteral("tiles/%1%2.%3");
    const QUrlQuery m_query = QStringLiteral("g=%1&mkt=%2");*/
};

class BingRoadMapProvider : public BingMapProvider
{
public:
    BingRoadMapProvider()
        : BingMapProvider(
            QObject::tr("Bing Road Map"),
            QStringLiteral("r"),
            QStringLiteral("png"),
            AVERAGE_BING_STREET_MAP,
            MapProvider::StreetMap) {}
};

class BingSatelliteMapProvider : public BingMapProvider
{
public:
    BingSatelliteMapProvider()
        : BingMapProvider(
            QObject::tr("Bing Satellite Map"),
            QStringLiteral("a"),
            QStringLiteral("jpg"),
            AVERAGE_BING_SAT_MAP,
            MapProvider::SatelliteMapDay) {}
};

class BingHybridMapProvider : public BingMapProvider
{
public:
    BingHybridMapProvider()
        : BingMapProvider(
            QObject::tr("Bing Hybrid Map"),
            QStringLiteral("h"),
            QStringLiteral("jpg"),
            AVERAGE_BING_SAT_MAP,
            MapProvider::HybridMap) {}
};
