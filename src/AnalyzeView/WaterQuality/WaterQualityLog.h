#pragma once

#include <QtCore/QObject>
#include <QtCore/QStringList>
#include <QtCore/QVariantList>
#include <QtCore/QVector>
#include <QtQmlIntegration/QtQmlIntegration>

/// 水质监测数据（导入 Excel / CSV 后的内存模型）
///
/// 支持的文件：
///   · .xlsx  —— 用 QGC 现成的 QGCCompression（libarchive）解出 xl/worksheets/sheet1.xml
///               与 xl/sharedStrings.xml，再解析表格 XML（不引入任何新依赖）
///   · .csv   —— 逗号分隔文本（Excel/WPS 都能另存为）
///   （.xls 97-2003 二进制格式需要额外的第三方库，暂不支持）
///
/// 表格约定（自适应，无需固定列名）：
///   · 第 1 行是表头，除第 1 列外每个表头就是一条水质参数名；
///   · 第 1 列是时间：优先按日期时间文本解析，其次按数值（当作秒，或按 excelTimeBase 参数
///     当作 Excel 日期序列号）。
///
/// 时间轴的 X 值统一用 "秒"（相对导入数据的第一条记录），与板载日志页面一致，
/// 这样图表轴、光标、缩放都能直接复用同一套交互。
class WaterQualityLog : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    /// 是否已成功导入数据
    Q_PROPERTY(bool loaded READ loaded NOTIFY loadedChanged)
    /// 导入失败时的错误描述（空串表示无错误）
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged)
    /// 数据源文件名（用于界面显示）
    Q_PROPERTY(QString fileName READ fileName NOTIFY fileNameChanged)

    /// 参数名列表（表头，不含时间列），顺序与源表一致
    Q_PROPERTY(QStringList parameterNames READ parameterNames NOTIFY dataChanged)
    /// 采样点数量（行数）
    Q_PROPERTY(int sampleCount READ sampleCount NOTIFY dataChanged)
    /// 时间轴范围（秒，相对第一条记录）
    Q_PROPERTY(double minTime READ minTime NOTIFY dataChanged)
    Q_PROPERTY(double maxTime READ maxTime NOTIFY dataChanged)

public:
    explicit WaterQualityLog(QObject* parent = nullptr);
    ~WaterQualityLog() override;

    bool        loaded      () const { return _loaded; }
    QString     errorString () const { return _errorString; }
    QString     fileName    () const { return _fileName; }
    QStringList parameterNames() const { return _parameterNames; }
    int         sampleCount () const { return _times.count(); }
    double      minTime     () const { return _times.isEmpty() ? 0.0 : _times.first(); }
    double      maxTime     () const { return _times.isEmpty() ? 1.0 : _times.last(); }

    /// 导入文件（按扩展名分派）。成功返回 true，失败时 errorString 有描述。
    Q_INVOKABLE bool loadFile(const QString& filePath);

    /// 清空已导入的数据
    Q_INVOKABLE void clear(void);

    /// 指定参数在 [minTime, maxTime] 区间内的采样点，格式 [{x, y}, ...]。
    /// maxPoints 会按像素宽度降采样（<=0 表示不降采样），避免把几十万个点塞进图表。
    Q_INVOKABLE QVariantList samplesForParameter(const QString& parameterName,
                                                double minTime, double maxTime, int maxPoints) const;

    /// 指定参数在全量数据里的数值范围，返回 {min, max}；无数据时返回 {0, 1}
    Q_INVOKABLE QVariantMap parameterMinMax(const QString& parameterName) const;

    /// 热力图用：把 [minTime, maxTime] 均分成 columnCount 列，
    /// 返回每个（参数, 列）格的平均值，格式 [[row0...], [row1...], ...]（行=参数），
    /// 空格子用 NaN 表示，供界面直接做颜色映射。
    Q_INVOKABLE QVariantList heatmapGrid(double minTime, double maxTime, int columnCount);

private:
    bool _loadCsv (const QString& filePath);
    bool _loadXlsx(const QString& filePath);

    /// 把解析出来的表格（第一行表头、第一列时间）装进内存模型
    bool _buildFromTable(const QList<QStringList>& rows, const QString& fileName);

    /// 解析 "2026-09-18 12:30:00" / "2026/09/18 12:30" / ISO8601 / 纯数字（秒或 Excel 序列号）
    static bool _parseTimestamp(const QString& text, double* seconds);

    /// 参数名 -> 列下标（不含时间列，即列下标 >= 1）
    int _columnForParameter(const QString& parameterName) const;

    void _resetData(void);

    QStringList             _parameterNames;    ///< 参数名（列下标 1..n 对应 _parameterNames[0..n-1]）
    QVector<double>         _times;             ///< 每条记录的时间（秒，相对第一条）
    QVector<QVector<double>> _values;           ///< _values[参数下标][记录下标]，无数据用 NaN

    QString _fileName;
    QString _errorString;
    bool    _loaded = false;
};
