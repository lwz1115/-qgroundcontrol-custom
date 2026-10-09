#include "SpeedSection.h"
#include "SimpleMissionItem.h"
#include "PlanMasterController.h"
#include "Vehicle.h"
#include "QmlObjectListModel.h"
#include "SettingsManager.h"
#include "AppSettings.h"

const char* SpeedSection::_flightSpeedName = "FlightSpeed";

QMap<QString, FactMetaData*> SpeedSection::_metaDataMap;

SpeedSection::SpeedSection(PlanMasterController* masterController, QObject* parent)
    : Section               (masterController, parent)
    , _available            (false)
    , _dirty                (false)
    , _specifyFlightSpeed   (false)
    , _flightSpeedFact      (0, _flightSpeedName,   FactMetaData::valueTypeDouble)
{
    if (_metaDataMap.isEmpty()) {
        _metaDataMap = FactMetaData::createMapFromJsonFile(QStringLiteral(":/json/SpeedSection.FactMetaData.json"), nullptr /* metaDataParent */);
    }

    double flightSpeed = 0;
    // 航点速度记忆：统一用 autonomousNavSpeed（默认 1 m/s、记忆上次设置、上限 5 m/s），
    // 与航线工具条里的速度面板共用同一个记忆值。
    // 不要回退到 defaultCruiseSpeed/defaultHoverSpeed：无人船默认巡航速度可能大于 5 m/s，
    // 这既不符合本功能的限速，也不是用户上次确认的规划速度。
    AppSettings* appSettings = SettingsManager::instance()->appSettings();
    const double rememberedSpeed = appSettings->autonomousNavSpeed()->rawValue().toDouble();
    if (rememberedSpeed > 0.0) {
        flightSpeed = rememberedSpeed;
    } else {
        // 记忆值异常（0 或负数）时兜底用元数据默认值 1 m/s，不要碰载具的巡航速度
        flightSpeed = _metaDataMap[_flightSpeedName]->rawDefaultValue().toDouble();
        if (flightSpeed <= 0.0) {
            flightSpeed = 1.0;
        }
    }

    _metaDataMap[_flightSpeedName]->setRawDefaultValue(flightSpeed);
    _flightSpeedFact.setMetaData(_metaDataMap[_flightSpeedName]);
    _flightSpeedFact.setRawValue(flightSpeed);

    connect(this,               &SpeedSection::specifyFlightSpeedChanged,   this, &SpeedSection::settingsSpecifiedChanged);
    connect(&_flightSpeedFact,  &Fact::valueChanged,                        this, &SpeedSection::_flightSpeedChanged);

    connect(this,               &SpeedSection::specifyFlightSpeedChanged,   this, &SpeedSection::_updateSpecifiedFlightSpeed);
    connect(&_flightSpeedFact,  &Fact::valueChanged,                        this, &SpeedSection::_updateSpecifiedFlightSpeed);
}

bool SpeedSection::settingsSpecified(void) const
{
    return _specifyFlightSpeed;
}

void SpeedSection::setAvailable(bool available)
{
    if (available != _available) {
        // 地面无人船（rover/sub）同样需要能设置航行速度：ArduPilot Rover 支持
        // MAV_CMD_DO_CHANGE_SPEED 的地面速度（param1=1）。原先只放开 multiRotor/fixedWing，
        // 导致无人船的 _available 永远为 false，scanForSection 直接返回、appendSectionItems
        // 也拿不到调用，地面站设置的速度压根不会写进任务，船只能按飞控默认巡航速度跑。
        if (available && (_masterController->controllerVehicle()->multiRotor()
                          || _masterController->controllerVehicle()->fixedWing()
                          || _masterController->controllerVehicle()->rover()
                          || _masterController->controllerVehicle()->sub())) {
            _available = available;
            emit availableChanged(available);
        }
    }
}

void SpeedSection::setDirty(bool dirty)
{
    if (_dirty != dirty) {
        _dirty = dirty;
        emit dirtyChanged(_dirty);
    }
}

void SpeedSection::setSpecifyFlightSpeed(bool specifyFlightSpeed)
{
    if (specifyFlightSpeed != _specifyFlightSpeed) {
        _specifyFlightSpeed = specifyFlightSpeed;
        emit specifyFlightSpeedChanged(specifyFlightSpeed);
        setDirty(true);
        emit itemCountChanged(itemCount());
    }
}

int SpeedSection::itemCount(void) const
{
    // DO_CHANGE_SPEED 是真实 MAVLink 任务项，必须计入协议序号才能与 MISSION_CURRENT / DO_JUMP 对齐。
    return _specifyFlightSpeed ? 1 : 0;
}

void SpeedSection::appendSectionItems(QList<MissionItem*>& items, QObject* missionItemParent, int& seqNum)
{
    // IMPORTANT NOTE: If anything changes here you must also change SpeedSection::scanForSettings

    if (_specifyFlightSpeed) {
        // 地面无人船（rover/sub）用地面速度（param1=1），不能用空速（param1=0）：
        // ArduPilot Rover 没有空速概念，原先对非 multiRotor 一律发空速命令会被飞控忽略，
        // 船仍按自身巡航速度（如 10 m/s）走，导致地面站设置的速度不生效。
        // 只有固定翼才用空速。
        const bool useGroundspeed = _masterController->controllerVehicle()->multiRotor()
                                    || _masterController->controllerVehicle()->rover()
                                    || _masterController->controllerVehicle()->sub();
        MissionItem* item = new MissionItem(seqNum++,
                                            MAV_CMD_DO_CHANGE_SPEED,
                                            MAV_FRAME_MISSION,
                                            useGroundspeed ? 1 /* groundspeed */ : 0 /* airspeed */,
                                            _flightSpeedFact.rawValue().toDouble(),
                                            -1,                                                                 // No throttle change
                                            0,                                                                  // Absolute speed change
                                            0, 0, 0,                                                            // param 5-7 not used
                                            true,                                                               // autoContinue
                                            false,                                                              // isCurrentItem
                                            missionItemParent);
        items.append(item);
    }
}

bool SpeedSection::scanForSection(QmlObjectListModel* visualItems, int scanIndex)
{
    if (!_available || scanIndex >= visualItems->count()) {
        return false;
    }

    SimpleMissionItem* item = visualItems->value<SimpleMissionItem*>(scanIndex);
    if (!item) {
        // We hit a complex item, there can't be a speed setting
        return false;
    }
    MissionItem& missionItem = item->missionItem();

    // See SpeedSection::appendMissionItems for specs on what consitutes a known speed setting

    if (missionItem.command() == MAV_CMD_DO_CHANGE_SPEED && missionItem.param3() == -1 && missionItem.param4() == 0 && missionItem.param5() == 0 && missionItem.param6() == 0 && missionItem.param7() == 0) {
        if (_masterController->controllerVehicle()->multiRotor() && missionItem.param1() != 1) {
            return false;
        } else if (_masterController->controllerVehicle()->fixedWing() && missionItem.param1() != 0) {
            return false;
        }
        visualItems->removeAt(scanIndex)->deleteLater();
        // 从任务恢复速度命令时把越界值钳制到有效范围（旧任务可能残留超过 5 m/s 上限的速度，
        // 例如 10.2 m/s）。
        const Fact* speedFact = SettingsManager::instance()->appSettings()->autonomousNavSpeed();
        const double minSpeed = speedFact->rawUserMin().isValid() ? speedFact->rawUserMin().toDouble() : 0.0;
        const double maxSpeed = speedFact->rawUserMax().isValid() ? speedFact->rawUserMax().toDouble() : std::numeric_limits<double>::max();
        _flightSpeedFact.setRawValue(qBound(minSpeed, missionItem.param2(), maxSpeed));
        setSpecifyFlightSpeed(true);
        return true;
    }

    return false;
}


double SpeedSection::specifiedFlightSpeed(void) const
{
    return _specifyFlightSpeed ? _flightSpeedFact.rawValue().toDouble() : std::numeric_limits<double>::quiet_NaN();
}

void SpeedSection::_updateSpecifiedFlightSpeed(void)
{
    if (_specifyFlightSpeed) {
        emit specifiedFlightSpeedChanged(specifiedFlightSpeed());
    }
}

void SpeedSection::_flightSpeedChanged(void)
{
    // We only set the dirty bit if specify flight speed it set. This allows us to change defaults for flight speed
    // without affecting dirty.
    if (_specifyFlightSpeed) {
        setDirty(true);
    }
}
