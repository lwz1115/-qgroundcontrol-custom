#pragma once

#include <QtCore/QObject>
#include <QtCore/QStringList>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>
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
/// 表格约定（自适应）：
///   · 表头行由列名关键字自动定位，不必在第 1 行（模版文件前 3 行是「监测数据 / 无人船 / 任务」标题）；
///   · 列名去括号（单位）后按别名匹配：时间 / 经度 / 纬度 / 电导率 / pH / 溶解氧 /
///     铵离子 / 叶绿素 / TAL-PC / 浊度（中英文别名都认，见 .cc 里的别名表）；
///   · 只有这七个参数会被载入，模版里其它列（温度 / 水深 / COD / 硝氮…）直接忽略；
///   · 时间列按日期时间文本解析，其次按数值（Excel 日期序列号范围内的大数值按序列号换算）。
///     一列关键字都认不出来时退回旧格式：第 1 行表头、第 1 列时间、其余列全是参数。
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

    /// 参数名列表（七个水质参数里表格实际含有的那些），顺序固定
    Q_PROPERTY(QStringList parameterNames READ parameterNames NOTIFY dataChanged)
    /// 采样点数量（行数）
    Q_PROPERTY(int sampleCount READ sampleCount NOTIFY dataChanged)
    /// 时间轴范围（秒，相对第一条记录）
    Q_PROPERTY(double minTime READ minTime NOTIFY dataChanged)
    Q_PROPERTY(double maxTime READ maxTime NOTIFY dataChanged)
    /// 表里是否带经纬度（没有经纬度就画不出地图路径）
    Q_PROPERTY(bool hasGeoData READ hasGeoData NOTIFY dataChanged)

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
    bool        hasGeoData  () const { return _hasGeoData; }

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

    /// 距离 time 最近的一个采样点，返回 {x, y}（无数据或该点为空值时返回空 map）。
    /// 悬停取值走这个接口：内部二分查找，避免鼠标每移动一次就线性扫描整列数据。
    Q_INVOKABLE QVariantMap sampleAt(const QString& parameterName, double time) const;

    /// 地图热力路径用：[minTime, maxTime] 内带经纬度的采样点，按时间顺序返回
    /// [{latitude, longitude, time, value}, ...]，value 为该参数在该点的数值（缺测为 NaN）。
    /// 没有经纬度的点会被跳过，不会画到 (0, 0) 上。
    /// maxPoints 会按时间分桶取平均（<=0 表示不降采样）：地图上每段折线都要单独建一个
    /// MapPolyline，段数直接决定渲染开销。
    Q_INVOKABLE QVariantList geoPathForParameter(const QString& parameterName,
                                                double minTime, double maxTime, int maxPoints) const;

signals:
    /// 数据是否已导入发生变化
    void loadedChanged();
    /// 错误描述发生变化
    void errorStringChanged();
    /// 数据源文件名发生变化
    void fileNameChanged();
    /// 参数名 / 采样点 / 时间范围 / 经纬度发生变化
    void dataChanged();

private:
    bool _loadCsv (const QString& filePath);
    bool _loadXlsx(const QString& filePath);

    /// 把解析出来的表格装进内存模型（自动定位表头行、按别名映射列）
    bool _buildFromTable(const QList<QStringList>& rows, const QString& fileName);

    /// 解析 "2026-09-18 12:30:00" / "2026/09/18 12:30" / ISO8601 / 纯数字（秒或 Excel 序列号）
    static bool _parseTimestamp(const QString& text, double* seconds);

    /// 参数名 -> 下标（对应 _values / _parameterNames）
    int _columnForParameter(const QString& parameterName) const;

    void _resetData(void);

    QStringList             _parameterNames;    ///< 参数名（下标与 _values 一一对应）
    QVector<double>         _times;             ///< 每条记录的时间（秒，相对第一条）
    QVector<QVector<double>> _values;           ///< _values[参数下标][记录下标]，无数据用 NaN
    QVector<double>         _longitudes;        ///< 每条记录的经度，缺失用 NaN
    QVector<double>         _latitudes;         ///< 每条记录的纬度，缺失用 NaN
    bool                    _hasGeoData = false;

    QString _fileName;
    QString _errorString;
    bool    _loaded = false;
};