.pragma library

/// 水质监测页面公共工具。
/// 折线图 / 热力图 / 页面三处都要把「秒」格式化成时间文本，逻辑完全一样，
/// 放在这里避免同一个函数抄三份后改漏。

/// 秒 -> "HH:MM:SS"
function timeText(seconds) {
    if (isNaN(seconds)) {
        return ""
    }
    const total = Math.max(0, Math.floor(seconds))
    return _two(Math.floor(total / 3600)) + ":" + _two(Math.floor(total / 60) % 60) + ":" + _two(total % 60)
}

/// 秒 -> "HH:MM"（跨度较大时坐标轴刻度用它，比 HH:MM:SS 短一半，避免标签互相重叠）
function timeTextShort(seconds) {
    if (isNaN(seconds)) {
        return ""
    }
    const total = Math.max(0, Math.floor(seconds))
    return _two(Math.floor(total / 3600)) + ":" + _two(Math.floor(total / 60) % 60)
}

/// 按跨度取一个「整齐」的刻度间隔（秒），把刻度数量控制在 5 个左右。
/// 交给坐标轴自动计算会给出十几个刻度，时间标签会挤成一团。
function niceTickInterval(span, tickCount) {
    const count = (tickCount > 0) ? tickCount : 5
    const hint = (span > 0 ? span : 1) / count
    const steps = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600,
                   7200, 10800, 21600, 43200, 86400]
    for (let i = 0; i < steps.length; i++) {
        if (steps[i] >= hint) {
            return steps[i]
        }
    }
    return steps[steps.length - 1]
}

function _two(value) {
    return value < 10 ? "0" + value : String(value)
}

/// 0..1 -> 热力颜色：蓝（低）→ 绿 → 黄 → 红（高）。
/// 直接对色相做线性插值会把中段全挤在青色附近，这里用明确的停靠点分段插值。
/// 折线图的地图路径与地图上的色带都用这一份映射，保证界面里的颜色含义一致。
function colorForNormalized(t) {
    if (isNaN(t)) {
        return "transparent"
    }
    const clamped = Math.max(0, Math.min(1, t))
    const stops = [
        { at: 0.00, hue: 240 },  // 蓝
        { at: 0.50, hue: 120 },  // 绿
        { at: 0.75, hue: 60 },   // 黄
        { at: 1.00, hue: 0 },    // 红
    ]
    let hue = stops[stops.length - 1].hue
    for (let i = 1; i < stops.length; i++) {
        if (clamped <= stops[i].at) {
            const lower = stops[i - 1]
            const upper = stops[i]
            const ratio = (clamped - lower.at) / (upper.at - lower.at)
            hue = lower.hue + (upper.hue - lower.hue) * ratio
            break
        }
    }
    return Qt.hsla(hue / 360, 0.85, 0.5, 1)
}
