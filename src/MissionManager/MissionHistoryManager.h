#pragma once

#include <QtCore/QDateTime>
#include <QtCore/QList>
#include <QtCore/QLoggingCategory>
#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QVariantList>
#include <QtQmlIntegration/QtQmlIntegration>

class PlanMasterController;
class QJSEngine;
class QQmlEngine;

Q_DECLARE_LOGGING_CATEGORY(MissionHistoryManagerLog)

/// @brief 规划任务历史：把当前规划另存为 .plan 快照，并可从历史回载。
///
/// 目录即列表、文件即内容：删除历史就是删文件，.plan 又是 QGC 标准任务格式，
/// 可脱离本程序手动备份/拷贝。上限 MaxHistoryCount 条，超出时按修改时间删除最旧的。
class MissionHistoryManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // Q_INVOKABLE 的参数需要 planController 是完整类型，而 moc 生成的代码
    // 才是真正实例化元类型的地方——用 Q_MOC_INCLUDE 把包含推迟到 moc 文件里，
    // 避免在头文件中拖入 PlanMasterController 的全部依赖。
    Q_MOC_INCLUDE("PlanMasterController.h")

    Q_PROPERTY(QVariantList historyList READ historyList NOTIFY historyListChanged)

public:
    static constexpr int MaxHistoryCount = 20;

    ~MissionHistoryManager() override;

    static MissionHistoryManager* instance();
    static MissionHistoryManager* create(QQmlEngine* qmlEngine, QJSEngine* jsEngine);

    /// 把 controller 的当前规划存入历史目录，文件名 = 任务名_时间戳.plan；name 为空时只保留时间戳
    Q_INVOKABLE bool saveCurrentPlan(PlanMasterController* controller, const QString& name);

    /// 按 historyList 中的 index 把对应快照回载到 controller
    Q_INVOKABLE bool loadHistory(PlanMasterController* controller, int index);

    /// 删除单条历史
    Q_INVOKABLE bool deleteHistory(int index);

    /// 删除历史目录下的全部快照
    Q_INVOKABLE void clearHistory();

    /// [{ name, time, index }]，按保存时间倒序
    [[nodiscard]] QVariantList historyList() const;

    [[nodiscard]] QString historyDirectory() const { return _historyDirectory; }

signals:
    void historyListChanged();

private:
    explicit MissionHistoryManager(QObject* parent = nullptr);

    struct Entry
    {
        QString   file;
        QString   name;
        QDateTime savedAt;
        qint64    size = 0;
    };

    [[nodiscard]] QList<Entry> _entries() const;
    void                       _ensureDirectory();
    void                       _trimToLimit();

    static QString _sanitizeName(const QString& name);
    static QString _readableSize(qint64 bytes);

    const QString _historyDirectory;
};
