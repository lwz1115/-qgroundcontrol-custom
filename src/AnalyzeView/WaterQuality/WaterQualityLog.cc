#include "WaterQualityLog.h"

#include "QGCCompression.h"
#include "QGCLoggingCategory.h"

#include <algorithm>

#include <QtCore/QDateTime>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QHash>
#include <QtCore/QRegularExpression>
#include <QtCore/QStringConverter>
#include <QtCore/QTextStream>
#include <QtCore/QXmlStreamReader>
#include <QtCore/QtMath>

QGC_LOGGING_CATEGORY(WaterQualityLogLog, "AnalyzeView.WaterQualityLog")

namespace {

/// Excel 日期序列号（1900 起算）转 Unix 纪元秒：25569 = 1970-01-01 的序列号
constexpr double kExcelEpochOffsetDays = 25569.0;
/// 数值落在这个区间时认为是 Excel 日期序列号（约 1954 年 ~ 2119 年）
constexpr double kExcelSerialMin = 20000.0;
constexpr double kExcelSerialMax = 80000.0;

/// 单元格引用（如 "AB12"）里的列号转 0 基下标；非法时返回 -1
int columnFromCellRef(const QString& cellRef)
{
    int column = 0;
    bool hasLetter = false;
    for (const QChar ch : cellRef) {
        if (!ch.isLetter()) {
            break;
        }
        column = (column * 26) + (ch.toUpper().unicode() - u'A' + 1);
        hasLetter = true;
    }
    return hasLetter ? column - 1 : -1;
}

/// 读一个 XML 元素内部的文本（不含子元素名），用于 <v>/<t>
QString elementText(QXmlStreamReader& reader)
{
    QString text;
    while (!reader.atEnd()) {
        reader.readNext();
        if (reader.isCharacters()) {
            text += reader.text().toString();
        } else if (reader.isEndElement()) {
            break;
        }
    }
    return text;
}

/// 归一化表头：丢掉括号里的单位（(mg/L)、（NTU））、空白与冒号，再转小写。
/// "溶解氧(mg/L)" -> "溶解氧"、"PH值" -> "ph值"、"TAL-PC" -> "tal-pc"
QString normalizeHeader(const QString& text)
{
    QString normalized;
    int depth = 0;
    for (const QChar ch : text) {
        if ((ch == u'(') || (ch == u'（')) {
            depth++;
            continue;
        }
        if ((ch == u')') || (ch == u'）')) {
            depth = qMax(0, depth - 1);
            continue;
        }
        if (depth > 0) {
            continue;
        }
        if (ch.isSpace() || (ch == u':') || (ch == u'：')) {
            continue;
        }
        normalized += ch.toLower();
    }
    return normalized;
}

/// 时间列的表头别名
const QStringList kTimeAliases = {
    QStringLiteral("时间"), QStringLiteral("日期"), QStringLiteral("日期时间"),
    QStringLiteral("采样时间"), QStringLiteral("采集时间"), QStringLiteral("记录时间"), QStringLiteral("监测时间"),
    QStringLiteral("time"), QStringLiteral("datetime"), QStringLiteral("timestamp"), QStringLiteral("date"),
};
/// 经度列的表头别名
const QStringList kLongitudeAliases = {
    QStringLiteral("经度"), QStringLiteral("longitude"), QStringLiteral("lon"),
    QStringLiteral("lng"), QStringLiteral("long"),
};
/// 纬度列的表头别名
const QStringList kLatitudeAliases = {
    QStringLiteral("纬度"), QStringLiteral("latitude"), QStringLiteral("lat"),
};

/// 七个水质参数及其表头别名（都是归一化后的精确匹配，避免 "DO"/"EC" 这类短词误命中别的列）
struct ParameterAlias {
    const char* canonical;
    const char* aliases[9];   ///< nullptr 结尾
};

const ParameterAlias kParameterAliases[] = {
    { "电导率", { "电导率", "电导", "导电率", "conductivity", "cond", "ec", "spcond", nullptr } },
    { "pH",     { "ph", "ph值", "酸碱度", nullptr } },
    { "溶解氧", { "溶解氧", "溶氧", "do", "dissolvedoxygen", "o2", nullptr } },
    { "铵离子", { "铵离子", "氨氮", "铵氮", "铵", "nh4", "nh4+", "nh4n", "ammonium", nullptr } },
    { "叶绿素", { "叶绿素", "叶绿素a", "chl", "chla", "chlorophyll", "chlorophylla", nullptr } },
    { "TAL-PC", { "talpc", "tal-pc", "tal_pc", "藻蓝蛋白", "藻蓝素", "蓝藻", "phycocyanin", "pc", nullptr } },
    { "浊度",   { "浊度", "turbidity", "turb", "ntu", nullptr } },
};

bool matchesAny(const QString& normalized, const QStringList& aliases)
{
    return aliases.contains(normalized);
}

/// 归一化后的列名 -> 七个参数里的规范名；不是这七个参数时返回空串
QString canonicalParameterName(const QString& normalizedHeader)
{
    for (const ParameterAlias& entry : kParameterAliases) {
        for (const char* alias : entry.aliases) {
            if (!alias) {
                break;
            }
            if (normalizedHeader == QLatin1String(alias)) {
                return QString::fromUtf8(entry.canonical);
            }
        }
    }
    return QString();
}

/// 在前若干行里找表头行：命中「时间 / 经度 / 纬度 / 七个参数」关键字的列数最多的一行。
/// 模版文件前 3 行是标题文字，表头在第 4 行，所以不能把第 1 行当表头。
/// 一处关键字都认不出来时返回 -1，由调用方退回旧格式。
int findHeaderRow(const QList<QStringList>& rows)
{
    const int scanLimit = qMin(rows.count(), 30);
    int bestRow  = -1;
    int bestHits = 0;

    for (int row = 0; row < scanLimit; row++) {
        int hits = 0;
        for (const QString& cell : rows.at(row)) {
            const QString normalized = normalizeHeader(cell);
            if (normalized.isEmpty()) {
                continue;
            }
            if (matchesAny(normalized, kTimeAliases) || matchesAny(normalized, kLongitudeAliases) ||
                matchesAny(normalized, kLatitudeAliases) || !canonicalParameterName(normalized).isEmpty()) {
                hits++;
            }
        }
        if (hits > bestHits) {
            bestHits = hits;
            bestRow  = row;
        }
    }

    // 至少命中两列才认成表头：一行里单独一个词恰好同名（比如数据里出现 "EC" 文本）说明不了问题
    return (bestHits >= 2) ? bestRow : -1;
}

/// 取第 column 列的文本（越界或 column < 0 时返回空串）
QString cellAt(const QStringList& cells, int column)
{
    return ((column >= 0) && (column < cells.count())) ? cells.at(column).trimmed() : QString();
}

/// 文本转数值，空串或非数值返回 NaN
double numberOrNaN(const QString& text)
{
    bool ok = false;
    const double value = text.toDouble(&ok);
    return ok ? value : qQNaN();
}

}  // namespace

WaterQualityLog::WaterQualityLog(QObject* parent)
    : QObject(parent)
{
}

WaterQualityLog::~WaterQualityLog() = default;

void WaterQualityLog::clear(void)
{
    _resetData();
    _fileName.clear();
    _errorString.clear();
    _loaded = false;

    emit fileNameChanged();
    emit errorStringChanged();
    emit loadedChanged();
    emit dataChanged();
}

void WaterQualityLog::_resetData(void)
{
    _parameterNames.clear();
    _times.clear();
    _values.clear();
    _longitudes.clear();
    _latitudes.clear();
    _hasGeoData = false;
}

bool WaterQualityLog::loadFile(const QString& filePath)
{
    if (filePath.isEmpty()) {
        _errorString = tr("No file selected");
        emit errorStringChanged();
        return false;
    }

    const QFileInfo fileInfo(filePath);
    if (!fileInfo.exists() || !fileInfo.isFile()) {
        _errorString = tr("File does not exist: %1").arg(filePath);
        emit errorStringChanged();
        return false;
    }

    const QString suffix = fileInfo.suffix().toLower();
    bool success = false;

    if (suffix == QStringLiteral("xlsx")) {
        success = _loadXlsx(filePath);
    } else if ((suffix == QStringLiteral("csv")) || (suffix == QStringLiteral("txt"))) {
        success = _loadCsv(filePath);
    } else if (suffix == QStringLiteral("xls")) {
        _errorString = tr("The legacy .xls format is not supported yet. Save it as .xlsx or .csv and import again.");
        success = false;
    } else {
        _errorString = tr("Unsupported file type .%1 (supported: .xlsx, .csv)").arg(suffix);
        success = false;
    }

    if (!success) {
        // 导入失败时清掉旧数据，避免界面残留上一次导入的曲线与参数
        _resetData();
        _fileName.clear();
    }
    _loaded = success;
    if (success) {
        _fileName    = fileInfo.fileName();
        _errorString = QString();
        qCDebug(WaterQualityLogLog) << "已导入水质数据" << _fileName
                                    << "参数数:" << _parameterNames.count()
                                    << "记录数:" << _times.count();
    }

    emit fileNameChanged();
    emit errorStringChanged();
    emit loadedChanged();
    emit dataChanged();

    return success;
}

// ---------------------------------------------------------------------------
// CSV
// ---------------------------------------------------------------------------

bool WaterQualityLog::_loadCsv(const QString& filePath)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        _errorString = tr("Unable to open file: %1").arg(file.errorString());
        return false;
    }

    QTextStream stream(&file);
    // Excel 另存的 CSV 常见是本地编码（GBK），先按 UTF-8 解码，失败再按本地 8 位编码处理
    stream.setEncoding(QStringConverter::Utf8);

    QList<QStringList> rows;
    while (!stream.atEnd()) {
        const QString line = stream.readLine();
        if (line.trimmed().isEmpty()) {
            continue;
        }

        // 逐字符解析，支持引号包裹的字段（字段内可含逗号与转义的双引号）
        QStringList fields;
        QString     field;
        bool        inQuotes = false;
        for (int i = 0; i < line.length(); i++) {
            const QChar ch = line.at(i);
            if (inQuotes) {
                if (ch == u'"') {
                    if ((i + 1 < line.length()) && (line.at(i + 1) == u'"')) {
                        field += u'"';
                        i++;
                    } else {
                        inQuotes = false;
                    }
                } else {
                    field += ch;
                }
            } else if (ch == u'"') {
                inQuotes = true;
            } else if ((ch == u',') || (ch == u';') || (ch == u'\t')) {
                fields.append(field.trimmed());
                field.clear();
            } else {
                field += ch;
            }
        }
        fields.append(field.trimmed());
        rows.append(fields);
    }

    if (rows.isEmpty()) {
        _errorString = tr("The file contains no usable data rows");
        return false;
    }

    return _buildFromTable(rows, QFileInfo(filePath).fileName());
}

// ---------------------------------------------------------------------------
// xlsx：先解出表格 XML，再当普通表格解析
// ---------------------------------------------------------------------------

bool WaterQualityLog::_loadXlsx(const QString& filePath)
{
    // 表格名可能是 sheet1.xml、sheet2.xml…… 用压缩模块列目录，取第一个工作表
    // （.xlsx 不是标准 zip 扩展名，显式指定 ZIP 格式，避免自动探测失败）
    QString tablePath;
    const QStringList entries = QGCCompression::listArchive(filePath, QGCCompression::Format::ZIP);
    for (const QString& entry : entries) {
        if (entry.startsWith(QStringLiteral("xl/worksheets/")) &&
            entry.endsWith(QStringLiteral(".xml")) &&
            !entry.contains(QStringLiteral("_rels"))) {
            tablePath = entry;
            break;
        }
    }
    if (tablePath.isEmpty()) {
        _errorString = tr("No worksheet found in this xlsx file (it may not be a valid Excel file)");
        return false;
    }

    const QByteArray tableXml = QGCCompression::extractFileData(filePath, tablePath, QGCCompression::Format::ZIP);
    if (tableXml.isEmpty()) {
        const QString error = QGCCompression::lastErrorString();
        _errorString = tr("Failed to read the worksheet: %1").arg(error.isEmpty() ? tr("empty data") : error);
        return false;
    }

    // 共享字符串表：单元格 t="s" 时存的是这里的下标
    QStringList sharedStrings;
    const QByteArray sharedXml = QGCCompression::extractFileData(filePath, QStringLiteral("xl/sharedStrings.xml"),
                                                                 QGCCompression::Format::ZIP);
    if (!sharedXml.isEmpty()) {
        QXmlStreamReader reader(sharedXml);
        QString current;
        while (!reader.atEnd()) {
            reader.readNext();
            if (reader.isStartElement()) {
                if (reader.name() == QStringLiteral("si")) {
                    current.clear();
                } else if (reader.name() == QStringLiteral("t")) {
                    current += elementText(reader);
                }
            } else if (reader.isEndElement() && (reader.name() == QStringLiteral("si"))) {
                sharedStrings.append(current);
            }
        }
    }

    QList<QStringList> rows;
    QXmlStreamReader reader(tableXml);
    QStringList row;
    while (!reader.atEnd()) {
        reader.readNext();
        if (reader.isStartElement()) {
            if (reader.name() == QStringLiteral("row")) {
                row.clear();
            } else if (reader.name() == QStringLiteral("c")) {
                const QXmlStreamAttributes attrs = reader.attributes();
                const int column = columnFromCellRef(attrs.value(QStringLiteral("r")).toString());
                const QString cellType = attrs.value(QStringLiteral("t")).toString();

                QString cellText;
                while (!reader.atEnd()) {
                    reader.readNext();
                    if (reader.isStartElement() && (reader.name() == QStringLiteral("v"))) {
                        cellText = elementText(reader);
                    } else if (reader.isStartElement() && (reader.name() == QStringLiteral("is"))) {
                        // 内联字符串：<is><t>文本</t></is>
                        while (!reader.atEnd()) {
                            reader.readNext();
                            if (reader.isStartElement() && (reader.name() == QStringLiteral("t"))) {
                                cellText += elementText(reader);
                            } else if (reader.isEndElement() && (reader.name() == QStringLiteral("is"))) {
                                break;
                            }
                        }
                    } else if (reader.isEndElement() && (reader.name() == QStringLiteral("c"))) {
                        break;
                    }
                }

                if (cellType == QStringLiteral("s")) {
                    const int index = cellText.toInt();
                    cellText = (index >= 0 && index < sharedStrings.count()) ? sharedStrings.at(index) : QString();
                }

                if (column >= 0) {
                    // 单元格可能跳过（空单元格不写），这里按列号补齐
                    while (row.count() <= column) {
                        row.append(QString());
                    }
                    row[column] = cellText;
                }
            }
        } else if (reader.isEndElement() && (reader.name() == QStringLiteral("row"))) {
            if (!row.isEmpty()) {
                rows.append(row);
            }
            row.clear();
        }
    }

    if (rows.isEmpty()) {
        _errorString = tr("The worksheet contains no usable data rows");
        return false;
    }

    return _buildFromTable(rows, QFileInfo(filePath).fileName());
}

// ---------------------------------------------------------------------------
// 表格 -> 内存模型
// ---------------------------------------------------------------------------

bool WaterQualityLog::_buildFromTable(const QList<QStringList>& rows, const QString& fileName)
{
    Q_UNUSED(fileName);

    if (rows.count() < 2) {
        _errorString = tr("At least one header row and one data row are required");
        return false;
    }

    // 表头不一定在第 1 行（模版文件前 3 行是「监测数据 / 无人船 / 任务」标题），
    // 先按列名关键字定位；一处关键字都认不出来时退回旧格式（第 1 行表头、第 1 列时间）。
    const int detectedHeaderRow = findHeaderRow(rows);
    const int headerRow = (detectedHeaderRow >= 0) ? detectedHeaderRow : 0;
    if (headerRow >= (rows.count() - 1)) {
        _errorString = tr("The table contains a header row but no data rows");
        return false;
    }

    const QStringList& header = rows.at(headerRow);

    int          timeColumn = -1;
    int          lonColumn  = -1;
    int          latColumn  = -1;
    QStringList  parameterNames;
    QVector<int> parameterColumns;

    if (detectedHeaderRow < 0) {
        timeColumn = 0;
        for (int column = 1; column < header.count(); column++) {
            const QString name = header.at(column).trimmed();
            parameterNames.append(name.isEmpty() ? tr("Parameter %1").arg(column) : name);
            parameterColumns.append(column);
        }
    } else {
        QHash<QString, int> parameterColumnByName;
        QStringList         unmatchedNames;
        QVector<int>        unmatchedColumns;

        for (int column = 0; column < header.count(); column++) {
            const QString normalized = normalizeHeader(header.at(column));
            if (normalized.isEmpty()) {
                continue;
            }
            if (matchesAny(normalized, kTimeAliases)) {
                if (timeColumn < 0) {
                    timeColumn = column;
                }
                continue;
            }
            if (matchesAny(normalized, kLongitudeAliases)) {
                if (lonColumn < 0) {
                    lonColumn = column;
                }
                continue;
            }
            if (matchesAny(normalized, kLatitudeAliases)) {
                if (latColumn < 0) {
                    latColumn = column;
                }
                continue;
            }

            const QString canonical = canonicalParameterName(normalized);
            if (canonical.isEmpty()) {
                // 七个参数以外的列（温度 / 水深 / COD / 硝氮…）：只有在七个参数一个都没认出来时才会用到
                unmatchedNames.append(header.at(column).trimmed());
                unmatchedColumns.append(column);
            } else if (!parameterColumnByName.contains(canonical)) {
                // 同名参数列只取第一列
                parameterColumnByName.insert(canonical, column);
            }
        }

        // 固定按七个参数的顺序展示（模版里列序不同，叶绿素排在电导率前面）
        for (const ParameterAlias& entry : kParameterAliases) {
            const QString canonical = QString::fromUtf8(entry.canonical);
            const auto it = parameterColumnByName.constFind(canonical);
            if (it != parameterColumnByName.constEnd()) {
                parameterNames.append(canonical);
                parameterColumns.append(it.value());
            }
        }
        if (parameterNames.isEmpty()) {
            // 一个已知参数都没有（例如把普通 CSV 当水质表导入）：退回「除时间 / 经纬度外的列都是参数」，
            // 否则这类文件会一列都识别不出来
            for (int i = 0; i < unmatchedNames.count(); i++) {
                parameterNames.append(unmatchedNames.at(i).isEmpty()
                                      ? tr("Parameter %1").arg(unmatchedColumns.at(i)) : unmatchedNames.at(i));
                parameterColumns.append(unmatchedColumns.at(i));
            }
        }
        if (timeColumn < 0) {
            _errorString = tr("The header row has no time column");
            return false;
        }
    }

    QVector<double>          times;
    QVector<double>          longitudes;
    QVector<double>          latitudes;
    QVector<QVector<double>> values(parameterColumns.count());

    double firstTimestamp = qQNaN();
    bool   hasGeoData     = false;

    for (int rowIndex = headerRow + 1; rowIndex < rows.count(); rowIndex++) {
        const QStringList& cells = rows.at(rowIndex);
        if (cells.isEmpty()) {
            continue;
        }

        double timestamp = 0.0;
        if (!_parseTimestamp(cellAt(cells, timeColumn), &timestamp)) {
            // 时间列解析不出来就跳过这一行（表尾常有汇总行 / 空行）
            continue;
        }
        if (qIsNaN(firstTimestamp)) {
            firstTimestamp = timestamp;
        }
        times.append(timestamp - firstTimestamp);

        double latitude  = numberOrNaN(cellAt(cells, latColumn));
        double longitude = numberOrNaN(cellAt(cells, lonColumn));
        if (qIsNaN(latitude) || qIsNaN(longitude) ||
            (latitude < -90.0) || (latitude > 90.0) || (longitude < -180.0) || (longitude > 180.0)) {
            // 无效坐标统一记 NaN：地图路径要把这些点跳过去，而不是画到 (0, 0) 上
            latitude  = qQNaN();
            longitude = qQNaN();
        } else {
            hasGeoData = true;
        }
        latitudes.append(latitude);
        longitudes.append(longitude);

        for (int i = 0; i < parameterColumns.count(); i++) {
            values[i].append(numberOrNaN(cellAt(cells, parameterColumns.at(i))));
        }
    }

    if (times.isEmpty()) {
        _errorString = tr("No valid timestamps found in the time column");
        return false;
    }
    // 时间必须递增，图表轴才正常
    for (int i = 1; i < times.count(); i++) {
        if (times.at(i) < times.at(i - 1)) {
            times[i] = times.at(i - 1);
        }
    }

    _resetData();
    _parameterNames = parameterNames;
    _times          = times;
    _values         = values;
    _longitudes     = longitudes;
    _latitudes      = latitudes;
    _hasGeoData     = hasGeoData;

    return true;
}

bool WaterQualityLog::_parseTimestamp(const QString& text, double* seconds)
{
    const QString trimmed = text.trimmed();
    if (trimmed.isEmpty()) {
        return false;
    }

    // 1) 数值：可能是相对秒、Unix 秒，也可能是 Excel 日期序列号
    bool ok = false;
    const double number = trimmed.toDouble(&ok);
    if (ok) {
        if ((number >= kExcelSerialMin) && (number <= kExcelSerialMax)) {
            *seconds = (number - kExcelEpochOffsetDays) * 86400.0;
        } else {
            *seconds = number;
        }
        return true;
    }

    // 2) 日期时间文本
    static const QStringList formats = {
        QStringLiteral("yyyy-MM-dd HH:mm:ss.zzz"),
        QStringLiteral("yyyy-MM-dd HH:mm:ss"),
        QStringLiteral("yyyy-MM-dd HH:mm"),
        QStringLiteral("yyyy/MM/dd HH:mm:ss"),
        QStringLiteral("yyyy/MM/dd HH:mm"),
        QStringLiteral("yyyy-M-d H:m:s"),
        QStringLiteral("yyyy-M-d H:m"),
        QStringLiteral("MM/dd/yyyy HH:mm:ss"),
        QStringLiteral("dd/MM/yyyy HH:mm:ss"),
        QStringLiteral("yyyyMMddHHmmss"),
        QStringLiteral("HH:mm:ss"),
        QStringLiteral("HH:mm"),
    };
    for (const QString& format : formats) {
        QDateTime dateTime = QDateTime::fromString(trimmed, format);
        if (dateTime.isValid()) {
            // 只有时间的格式（HH:mm:ss）按当天 0 点起算偏移
            if ((format == QStringLiteral("HH:mm:ss")) || (format == QStringLiteral("HH:mm"))) {
                *seconds = dateTime.time().msecsSinceStartOfDay() / 1000.0;
            } else {
                *seconds = static_cast<double>(dateTime.toSecsSinceEpoch());
            }
            return true;
        }
    }

    // 3) ISO8601（带时区）
    const QDateTime isoDateTime = QDateTime::fromString(trimmed, Qt::ISODateWithMs);
    if (isoDateTime.isValid()) {
        *seconds = static_cast<double>(isoDateTime.toSecsSinceEpoch());
        return true;
    }

    return false;
}

// ---------------------------------------------------------------------------
// 查询接口
// ---------------------------------------------------------------------------

int WaterQualityLog::_columnForParameter(const QString& parameterName) const
{
    const int index = _parameterNames.indexOf(parameterName);
    return (index >= 0 && index < _values.count()) ? index : -1;
}

QVariantList WaterQualityLog::samplesForParameter(const QString& parameterName,
                                                 double minTime, double maxTime, int maxPoints) const
{
    QVariantList samples;
    const int column = _columnForParameter(parameterName);
    if ((column < 0) || _times.isEmpty()) {
        return samples;
    }

    const QVector<double>& columnValues = _values.at(column);

    // 先取出区间内的点
    QVector<int> indices;
    for (int i = 0; i < _times.count(); i++) {
        const double t = _times.at(i);
        if (t < minTime) {
            continue;
        }
        if (t > maxTime) {
            break;
        }
        if (!qIsNaN(columnValues.at(i))) {
            indices.append(i);
        }
    }
    if (indices.isEmpty()) {
        return samples;
    }

    // 按像素宽度分桶取平均，避免点数远超像素导致图表卡顿
    if ((maxPoints > 0) && (indices.count() > maxPoints)) {
        const int bucketCount = qMax(1, maxPoints);
        const double span = qMax(1e-9, maxTime - minTime);
        QVector<double> sumTime(bucketCount, 0.0);
        QVector<double> sumValue(bucketCount, 0.0);
        QVector<int>    bucketHits(bucketCount, 0);

        for (const int index : indices) {
            const double t = _times.at(index);
            int bucket = static_cast<int>(((t - minTime) / span) * bucketCount);
            bucket = qBound(0, bucket, bucketCount - 1);
            sumTime[bucket]   += t;
            sumValue[bucket]  += columnValues.at(index);
            bucketHits[bucket]++;
        }

        for (int bucket = 0; bucket < bucketCount; bucket++) {
            if (bucketHits.at(bucket) == 0) {
                continue;
            }
            QVariantMap point;
            point.insert(QStringLiteral("x"), sumTime.at(bucket) / bucketHits.at(bucket));
            point.insert(QStringLiteral("y"), sumValue.at(bucket) / bucketHits.at(bucket));
            samples.append(point);
        }
        return samples;
    }

    samples.reserve(indices.count());
    for (const int index : indices) {
        QVariantMap point;
        point.insert(QStringLiteral("x"), _times.at(index));
        point.insert(QStringLiteral("y"), columnValues.at(index));
        samples.append(point);
    }
    return samples;
}

QVariantMap WaterQualityLog::parameterMinMax(const QString& parameterName) const
{
    QVariantMap result;
    result.insert(QStringLiteral("min"), 0.0);
    result.insert(QStringLiteral("max"), 1.0);

    const int column = _columnForParameter(parameterName);
    if (column < 0) {
        return result;
    }

    double minValue = qQNaN();
    double maxValue = qQNaN();
    for (const double value : _values.at(column)) {
        if (qIsNaN(value)) {
            continue;
        }
        if (qIsNaN(minValue) || (value < minValue)) {
            minValue = value;
        }
        if (qIsNaN(maxValue) || (value > maxValue)) {
            maxValue = value;
        }
    }

    if (qIsNaN(minValue) || qIsNaN(maxValue)) {
        return result;
    }
    if (qFuzzyCompare(minValue, maxValue)) {
        maxValue = minValue + 1.0;
    }

    result[QStringLiteral("min")] = minValue;
    result[QStringLiteral("max")] = maxValue;
    return result;
}

QVariantMap WaterQualityLog::sampleAt(const QString& parameterName, double time) const
{
    QVariantMap result;
    const int column = _columnForParameter(parameterName);
    if ((column < 0) || _times.isEmpty()) {
        return result;
    }

    // _times 非递减，二分找到第一个不小于 time 的记录，再和它前一条比谁更近
    const auto begin = _times.cbegin();
    const auto end   = _times.cend();
    auto it = std::lower_bound(begin, end, time);
    if (it == end) {
        --it;
    } else if ((it != begin) && ((time - *(it - 1)) <= (*it - time))) {
        --it;
    }

    const int index = static_cast<int>(it - begin);
    const double value = _values.at(column).at(index);
    if (qIsNaN(value)) {
        return result;
    }

    result.insert(QStringLiteral("x"), _times.at(index));
    result.insert(QStringLiteral("y"), value);
    return result;
}

QVariantList WaterQualityLog::geoPathForParameter(const QString& parameterName,
                                                 double minTime, double maxTime, int maxPoints) const
{
    QVariantList path;
    if (!_hasGeoData || _times.isEmpty()) {
        return path;
    }

    const int column = _columnForParameter(parameterName);
    const QVector<double>* columnValues = (column >= 0) ? &_values.at(column) : nullptr;

    // 先取出区间内坐标有效的点（没经纬度的记录不能画到路径上）
    QVector<int> indices;
    for (int i = 0; i < _times.count(); i++) {
        const double t = _times.at(i);
        if (t < minTime) {
            continue;
        }
        if (t > maxTime) {
            break;
        }
        if (qIsNaN(_latitudes.at(i)) || qIsNaN(_longitudes.at(i))) {
            continue;
        }
        indices.append(i);
    }
    if (indices.isEmpty()) {
        return path;
    }

    const auto appendPoint = [&path](double latitude, double longitude, double time, double value) {
        QVariantMap point;
        point.insert(QStringLiteral("latitude"), latitude);
        point.insert(QStringLiteral("longitude"), longitude);
        point.insert(QStringLiteral("time"), time);
        point.insert(QStringLiteral("value"), value);
        path.append(point);
    };

    // 按时间分桶取平均：地图上每一段折线都要单独建一个 MapPolyline，段数直接决定渲染开销
    if ((maxPoints > 0) && (indices.count() > maxPoints)) {
        const int bucketCount = qMax(1, maxPoints);
        const double span = qMax(1e-9, maxTime - minTime);
        QVector<double> sumLat(bucketCount, 0.0);
        QVector<double> sumLon(bucketCount, 0.0);
        QVector<double> sumTime(bucketCount, 0.0);
        QVector<double> sumValue(bucketCount, 0.0);
        QVector<int>    hits(bucketCount, 0);
        QVector<int>    valueHits(bucketCount, 0);

        for (const int index : indices) {
            int bucket = static_cast<int>(((_times.at(index) - minTime) / span) * bucketCount);
            bucket = qBound(0, bucket, bucketCount - 1);
            sumLat[bucket]  += _latitudes.at(index);
            sumLon[bucket]  += _longitudes.at(index);
            sumTime[bucket] += _times.at(index);
            hits[bucket]++;
            if (columnValues) {
                const double value = columnValues->at(index);
                if (!qIsNaN(value)) {
                    sumValue[bucket] += value;
                    valueHits[bucket]++;
                }
            }
        }

        for (int bucket = 0; bucket < bucketCount; bucket++) {
            if (hits.at(bucket) == 0) {
                continue;
            }
            const double value = (valueHits.at(bucket) > 0) ? (sumValue.at(bucket) / valueHits.at(bucket)) : qQNaN();
            appendPoint(sumLat.at(bucket) / hits.at(bucket), sumLon.at(bucket) / hits.at(bucket),
                        sumTime.at(bucket) / hits.at(bucket), value);
        }
        return path;
    }

    path.reserve(indices.count());
    for (const int index : indices) {
        const double value = columnValues ? columnValues->at(index) : qQNaN();
        appendPoint(_latitudes.at(index), _longitudes.at(index), _times.at(index), value);
    }
    return path;
}
