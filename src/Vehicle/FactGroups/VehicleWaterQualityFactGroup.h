#pragma once

#include "FactGroup.h"

#include <QtCore/QHash>

/// 水质参数仪（水质探头）遥测。
///
/// 数据来源：MAVLink 标准消息 NAMED_VALUE_FLOAT（msgid 251），驱动按
/// (name, value) 广播，name 为不带 '\0' 的定长 char[10]。
/// 本项目约定的 7 个名称：COND / PH / DO / NH4 / CHLOR / TALPC / TURB。
///
/// 两个易错点：
///   · 驱动走 send_to_active_channels()，USB 与数传同时连接时会收到重复消息，
///     这里按 (name, time_boot_ms) 去重，避免同一帧把时间戳刷新两次。
///   · 传感器无读数时发的是 NaN 而不是 0（浊度 0 NTU、铵离子 0 mg/L 都是合法读数），
///     所以界面必须判 isNaN 显示 "--"，绘图时产生断线；这里原样保留 NaN。
class VehicleWaterQualityFactGroup : public FactGroup
{
    Q_OBJECT
    Q_PROPERTY(Fact *conductivity    READ conductivity    CONSTANT)   ///< COND  电导率 μS/cm
    Q_PROPERTY(Fact *ph              READ ph              CONSTANT)   ///< PH    酸碱度
    Q_PROPERTY(Fact *dissolvedOxygen READ dissolvedOxygen CONSTANT)   ///< DO    光学溶解氧 mg/L
    Q_PROPERTY(Fact *ammonium        READ ammonium        CONSTANT)   ///< NH4   铵离子 mg/L
    Q_PROPERTY(Fact *chlorophyll     READ chlorophyll     CONSTANT)   ///< CHLOR 叶绿素 μg/L
    Q_PROPERTY(Fact *phycocyanin     READ phycocyanin     CONSTANT)   ///< TALPC 总藻类-藻蓝蛋白 cells/mL
    Q_PROPERTY(Fact *turbidity       READ turbidity       CONSTANT)   ///< TURB  浊度 NTU

public:
    explicit VehicleWaterQualityFactGroup(QObject *parent = nullptr);

    Fact *conductivity()    { return &_conductivityFact; }
    Fact *ph()              { return &_phFact; }
    Fact *dissolvedOxygen() { return &_dissolvedOxygenFact; }
    Fact *ammonium()        { return &_ammoniumFact; }
    Fact *chlorophyll()     { return &_chlorophyllFact; }
    Fact *phycocyanin()     { return &_phycocyaninFact; }
    Fact *turbidity()       { return &_turbidityFact; }

    /// 处理一条 NAMED_VALUE_FLOAT；不是我们关心的名称就当作没收到
    // Overrides from FactGroup
    void handleMessage(Vehicle *vehicle, const mavlink_message_t &message) final;

protected:
    void _handleNamedValueFloat(const mavlink_message_t &message);

    /// 按名称取对应的 Fact；不认识的名字返回 nullptr
    Fact *_factForName(const QString &name);

    Fact _conductivityFact    = Fact(0, QStringLiteral("conductivity"),    FactMetaData::valueTypeDouble);
    Fact _phFact              = Fact(0, QStringLiteral("ph"),              FactMetaData::valueTypeDouble);
    Fact _dissolvedOxygenFact = Fact(0, QStringLiteral("dissolvedOxygen"), FactMetaData::valueTypeDouble);
    Fact _ammoniumFact        = Fact(0, QStringLiteral("ammonium"),        FactMetaData::valueTypeDouble);
    Fact _chlorophyllFact     = Fact(0, QStringLiteral("chlorophyll"),     FactMetaData::valueTypeDouble);
    Fact _phycocyaninFact     = Fact(0, QStringLiteral("phycocyanin"),     FactMetaData::valueTypeDouble);
    Fact _turbidityFact       = Fact(0, QStringLiteral("turbidity"),       FactMetaData::valueTypeDouble);

    /// 各名称最近一次处理的 time_boot_ms，用于丢弃多通道重复帧
    QHash<QString, uint32_t> _lastTimeBootMsByName;
};
