#include "WaterQualityLog.h"

#include "QGCCompression.h"
#include "QGCLoggingCategory.h"

#include <QtCore/QDateTime>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
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

    const QStringList header = rows.first();
    if (header.count() < 2) {
        _errorString = tr("The table needs at least two columns: time in the first column, water quality parameters from the second column on");
        return false;
    }

    QVector<double>         times;
    QVector<QVector<double>> values;
    values.resize(qMax(0, header.count() - 1));

    double firstTimestamp = qQNaN();

    for (int rowIndex = 1; rowIndex < rows.count(); rowIndex++) {
        const QStringList& cells = rows.at(rowIndex);
        if (cells.isEmpty()) {
            continue;
        }

        double timestamp = 0.0;
        if (!_parseTimestamp(cells.first(), &timestamp)) {
            // 时间列解析不出来就跳过这一行（表尾常有汇总行/空行）
            continue;
        }
        if (qIsNaN(firstTimestamp)) {
            firstTimestamp = timestamp;
        }

        times.append(timestamp - firstTimestamp);
        for (int column = 1; column < header.count(); column++) {
            const QString text = (column < cells.count()) ? cells.at(column).trimmed() : QString();
            const double value = text.isEmpty() ? qQNaN() : text.toDouble();
            values[column - 1].append(text.isEmpty() ? qQNaN() : value);
        }
    }

    if (times.isEmpty()) {
        _errorString = tr("No valid timestamps found in the first column");
        return false;
    }
    // 时间必须递增，图表轴才正常
    for (int i = 1; i < times.count(); i++) {
        if (times.at(i) < times.at(i - 1)) {
            times[i] = times.at(i - 1);
        }
    }

    _resetData();
    for (int column = 1; column < header.count(); column++) {
        QString name = header.at(column).trimmed();
        if (name.isEmpty()) {
            name = tr("Parameter %1").arg(column);
        }
        _parameterNames.append(name);
    }
    _times  = times;
    _values = values;

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

QVariantList WaterQualityLog::heatmapGrid(double minTime, double maxTime, int columnCount)
{
    QVariantList grid;
    if ((columnCount <= 0) || _times.isEmpty() || _values.isEmpty()) {
        return grid;
    }

    const double span = qMax(1e-9, maxTime - minTime);
    const int rowCount = _values.count();

    QVector<QVector<double>> sum(rowCount, QVector<double>(columnCount, 0.0));
    QVector<QVector<int>>    hits(rowCount, QVector<int>(columnCount, 0));

    for (int i = 0; i < _times.count(); i++) {
        const double t = _times.at(i);
        if ((t < minTime) || (t > maxTime)) {
            continue;
        }
        int column = static_cast<int>(((t - minTime) / span) * columnCount);
        column = qBound(0, column, columnCount - 1);
        for (int row = 0; row < rowCount; row++) {
            const double value = _values.at(row).at(i);
            if (qIsNaN(value)) {
                continue;
            }
            sum[row][column]  += value;
            hits[row][column] += 1;
        }
    }

    for (int row = 0; row < rowCount; row++) {
        QVariantList rowValues;
        rowValues.reserve(columnCount);
        for (int column = 0; column < columnCount; column++) {
            if (hits.at(row).at(column) == 0) {
                rowValues.append(qQNaN());
            } else {
                rowValues.append(sum.at(row).at(column) / hits.at(row).at(column));
            }
        }
        grid.append(rowValues);
    }

    return grid;
}
