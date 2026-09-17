#include "MissionHistoryManager.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QRegularExpression>
#include <QtCore/QStandardPaths>
#include <QtCore/QStringList>
#include <QtCore/QVariantMap>

#include "PlanMasterController.h"
#include "QGCLoggingCategory.h"

QGC_LOGGING_CATEGORY(MissionHistoryManagerLog, "qgc.mission.missionhistory")

MissionHistoryManager::MissionHistoryManager(QObject* parent)
    : QObject(parent)
    , _historyDirectory(QDir(QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation))
                            .filePath(QCoreApplication::applicationName() + QStringLiteral("/MissionHistory")))
{
    _ensureDirectory();
}

MissionHistoryManager::~MissionHistoryManager() = default;

MissionHistoryManager* MissionHistoryManager::instance()
{
    static MissionHistoryManager* s_instance = nullptr;
    if (!s_instance) {
        s_instance = new MissionHistoryManager();
    }
    return s_instance;
}

MissionHistoryManager* MissionHistoryManager::create(QQmlEngine* qmlEngine, QJSEngine* jsEngine)
{
    Q_UNUSED(qmlEngine);
    Q_UNUSED(jsEngine);
    return instance();
}

bool MissionHistoryManager::saveCurrentPlan(PlanMasterController* controller, const QString& name)
{
    if (!controller) {
        qCWarning(MissionHistoryManagerLog) << "saveCurrentPlan: no controller";
        return false;
    }

    // 只有任务设置项、没有任何航点的空规划没有保存价值
    if (!controller->containsItems()) {
        qCWarning(MissionHistoryManagerLog) << "saveCurrentPlan: plan is empty";
        return false;
    }

    _ensureDirectory();

    const QDateTime now = QDateTime::currentDateTime();
    const QString planName = _sanitizeName(name);
    const QString baseName = QStringLiteral("%1_%2")
                                 .arg(planName.isEmpty() ? QStringLiteral("plan") : planName,
                                      now.toString(QStringLiteral("yyyyMMdd_HHmmss")));
    const QString filePath = QDir(_historyDirectory).filePath(baseName + QStringLiteral(".plan"));

    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qCWarning(MissionHistoryManagerLog) << "saveCurrentPlan: open failed" << filePath << file.errorString();
        return false;
    }

    // 复用 QGC 自身的任务序列化，避免自造格式与版本漂移
    const QByteArray json = controller->saveToJson().toJson();
    if (file.write(json) != json.size()) {
        qCWarning(MissionHistoryManagerLog) << "saveCurrentPlan: write failed" << filePath << file.errorString();
        file.close();
        QFile::remove(filePath);
        return false;
    }
    file.close();

    _trimToLimit();
    emit historyListChanged();
    return true;
}

bool MissionHistoryManager::loadHistory(PlanMasterController* controller, int index)
{
    if (!controller) {
        qCWarning(MissionHistoryManagerLog) << "loadHistory: no controller";
        return false;
    }

    const QList<Entry> entries = _entries();
    if ((index < 0) || (index >= entries.count())) {
        qCWarning(MissionHistoryManagerLog) << "loadHistory: bad index" << index;
        return false;
    }

    const QString filePath = entries.at(index).file;
    if (!QFile::exists(filePath)) {
        qCWarning(MissionHistoryManagerLog) << "loadHistory: missing file" << filePath;
        return false;
    }

    controller->loadFromFile(filePath);
    return true;
}

bool MissionHistoryManager::deleteHistory(int index)
{
    const QList<Entry> entries = _entries();
    if ((index < 0) || (index >= entries.count())) {
        qCWarning(MissionHistoryManagerLog) << "deleteHistory: bad index" << index;
        return false;
    }

    const QString filePath = entries.at(index).file;
    if (!QFile::remove(filePath)) {
        qCWarning(MissionHistoryManagerLog) << "deleteHistory: remove failed" << filePath;
        return false;
    }

    emit historyListChanged();
    return true;
}

void MissionHistoryManager::clearHistory()
{
    const QList<Entry> entries = _entries();
    if (entries.isEmpty()) {
        return;
    }

    for (const Entry& entry : entries) {
        if (!QFile::remove(entry.file)) {
            qCWarning(MissionHistoryManagerLog) << "clearHistory: remove failed" << entry.file;
        }
    }

    emit historyListChanged();
}

QVariantList MissionHistoryManager::historyList() const
{
    QVariantList list;
    const QList<Entry> entries = _entries();

    int index = 0;
    for (const Entry& entry : entries) {
        list.append(QVariantMap{
            { QStringLiteral("name"), entry.name },
            { QStringLiteral("time"), entry.savedAt.toString(QStringLiteral("yyyy-MM-dd HH:mm:ss")) },
            { QStringLiteral("size"), _readableSize(entry.size) },
            { QStringLiteral("index"), index++ },
        });
    }

    return list;
}

QList<MissionHistoryManager::Entry> MissionHistoryManager::_entries() const
{
    QList<Entry> entries;

    // QDir::Time 按修改时间倒序，最新保存的排在最前
    const QFileInfoList files = QDir(_historyDirectory).entryInfoList({ QStringLiteral("*.plan") }, QDir::Files, QDir::Time);
    static const QRegularExpression timestampSuffix(QStringLiteral("_\\d{8}_\\d{6}$"));

    for (const QFileInfo& fileInfo : files) {
        Entry entry;
        entry.file    = fileInfo.absoluteFilePath();
        entry.name    = fileInfo.completeBaseName();
        entry.savedAt = fileInfo.lastModified();
        entry.size    = fileInfo.size();
        entry.name.remove(timestampSuffix);
        entries.append(entry);
    }

    return entries;
}

void MissionHistoryManager::_ensureDirectory()
{
    QDir dir(_historyDirectory);
    if (!dir.exists() && !dir.mkpath(QStringLiteral("."))) {
        qCWarning(MissionHistoryManagerLog) << "Failed to create history directory" << _historyDirectory;
    }
}

void MissionHistoryManager::_trimToLimit()
{
    const QList<Entry> entries = _entries();
    for (int i = MaxHistoryCount; i < entries.count(); i++) {
        if (!QFile::remove(entries.at(i).file)) {
            qCWarning(MissionHistoryManagerLog) << "Failed to remove oldest history file" << entries.at(i).file;
        }
    }
}

QString MissionHistoryManager::_sanitizeName(const QString& name)
{
    QString sanitized = name.trimmed();

    static const QRegularExpression invalidChars(QStringLiteral("[\\\\/:*?\"<>|\\x00-\\x1f]"));
    sanitized.remove(invalidChars);

    // 为 _yyyyMMdd_HHmmss.plan 后缀和路径长度留出余量
    return sanitized.left(64);
}

QString MissionHistoryManager::_readableSize(qint64 bytes)
{
    static const QStringList units{ QStringLiteral("B"), QStringLiteral("KB"), QStringLiteral("MB") };

    double value = static_cast<double>(bytes);
    int unit = 0;
    while ((value >= 1024.0) && (unit < (units.count() - 1))) {
        value /= 1024.0;
        unit++;
    }

    return (unit == 0) ? QStringLiteral("%1 %2").arg(bytes).arg(units.at(unit))
                       : QStringLiteral("%1 %2").arg(value, 0, 'f', 1).arg(units.at(unit));
}
