#include "VehicleWaterQualityFactGroup.h"

#include <cstring>
#include <limits>

#include <QtCore/QString>

VehicleWaterQualityFactGroup::VehicleWaterQualityFactGroup(QObject *parent)
    : FactGroup(1000, QStringLiteral(":/json/Vehicle/WaterQualityFact.json"), parent)
{
    _addFact(&_conductivityFact);
    _addFact(&_phFact);
    _addFact(&_dissolvedOxygenFact);
    _addFact(&_ammoniumFact);
    _addFact(&_chlorophyllFact);
    _addFact(&_phycocyaninFact);
    _addFact(&_turbidityFact);

    // 初始值用 NaN 而不是 0：探头没配某个测量项时该名称根本不会上报，
    // 界面必须能区分「没数据」和「读数为 0」（浊度 0 NTU、铵离子 0 mg/L 都是合法读数）
    const double noValue = std::numeric_limits<double>::quiet_NaN();
    _conductivityFact.setRawValue(noValue);
    _phFact.setRawValue(noValue);
    _dissolvedOxygenFact.setRawValue(noValue);
    _ammoniumFact.setRawValue(noValue);
    _chlorophyllFact.setRawValue(noValue);
    _phycocyaninFact.setRawValue(noValue);
    _turbidityFact.setRawValue(noValue);
}

void VehicleWaterQualityFactGroup::handleMessage(Vehicle *vehicle, const mavlink_message_t &message)
{
    Q_UNUSED(vehicle);

    switch (message.msgid) {
    case MAVLINK_MSG_ID_NAMED_VALUE_FLOAT:
        _handleNamedValueFloat(message);
        break;
    default:
        break;
    }
}

Fact *VehicleWaterQualityFactGroup::_factForName(const QString &name)
{
    if (name == QStringLiteral("COND"))  return &_conductivityFact;
    if (name == QStringLiteral("PH"))    return &_phFact;
    if (name == QStringLiteral("DO"))    return &_dissolvedOxygenFact;
    if (name == QStringLiteral("NH4"))   return &_ammoniumFact;
    if (name == QStringLiteral("CHLOR")) return &_chlorophyllFact;
    if (name == QStringLiteral("TALPC")) return &_phycocyaninFact;
    if (name == QStringLiteral("TURB"))  return &_turbidityFact;
    return nullptr;
}

void VehicleWaterQualityFactGroup::_handleNamedValueFloat(const mavlink_message_t &message)
{
    mavlink_named_value_float_t namedValue{};
    mavlink_msg_named_value_float_decode(&message, &namedValue);

    // name 是定长 char[10]，协议上不保证以 '\0' 结尾，必须按实际长度截取；
    // 本项目发的名称最长 5 字符，剩余字节已被零填充，但这里不能依赖这一点
    const QString name = QString::fromLatin1(namedValue.name,
                                             static_cast<int>(strnlen(namedValue.name, sizeof(namedValue.name))));

    Fact *fact = _factForName(name);
    if (!fact) {
        // 不是水质参数仪的名称（其它组件也用 NAMED_VALUE_FLOAT），直接忽略
        return;
    }

    // 驱动走 send_to_active_channels()，发往所有活动通道：
    // USB 与数传同时连着时同一条数据会收到两次，按 (name, time_boot_ms) 去重
    const uint32_t timeBootMs = namedValue.time_boot_ms;
    auto it = _lastTimeBootMsByName.find(name);
    if ((it != _lastTimeBootMsByName.end()) && (it.value() == timeBootMs)) {
        return;
    }
    _lastTimeBootMsByName.insert(name, timeBootMs);

    // 传感器无读数时驱动发的是 NaN，原样保留：界面判 isNaN 显示 "--"，绘图时形成断线
    fact->setRawValue(static_cast<double>(namedValue.value));

    _setTelemetryAvailable(true);
}
