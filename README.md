<p align="center">
  <img src="https://raw.githubusercontent.com/Dronecode/UX-Design/35d8148a8a0559cd4bcf50bfa2c94614983cce91/QGC/Branding/Deliverables/QGC_RGB_Logo_Horizontal_Positive_PREFERRED/QGC_RGB_Logo_Horizontal_Positive_PREFERRED.svg" alt="QGroundControl Logo" width="500">
</p>

<p align="center">
  <a href="https://github.com/mavlink/QGroundControl/releases"><img src="https://img.shields.io/github/v/release/mavlink/QGroundControl" alt="最新发布"></a>
  <a href="https://github.com/mavlink/qgroundcontrol/blob/master/.github/COPYING.md"><img src="https://img.shields.io/github/license/mavlink/QGroundControl" alt="开源协议"></a>
  <a href="https://github.com/mavlink/QGroundControl/actions/workflows/linux.yml"><img src="https://github.com/mavlink/QGroundControl/actions/workflows/linux.yml/badge.svg" alt="Linux 构建"></a>
  <a href="https://securityscorecards.dev/viewer/?uri=github.com/mavlink/qgroundcontrol"><img src="https://img.shields.io/ossf-scorecard/github.com/mavlink/qgroundcontrol?label=openssf%20scorecard" alt="OpenSSF 安全评分卡"></a>
  <a href="https://crowdin.com/project/qgroundcontrol"><img src="https://badges.crowdin.net/qgroundcontrol/localized.svg" alt="Crowdin 本地化"></a>
  <a href="https://discord.com/channels/1022170275984457759/1022185820683255908"><img src="https://img.shields.io/discord/1022170275984457759?logo=discord&logoColor=white&label=Discord" alt="Dronecode Discord"></a>
  <a href="https://doi.org/10.5281/zenodo.595404"><img src="https://zenodo.org/badge/DOI/10.5281/zenodo.595404.svg" alt="DOI"></a>
</p>

## 项目说明

本仓库是 [QGroundControl](https://github.com/mavlink/QGroundControl)（QGC）的定制分支，面向**无人船水质监测**作业场景。原版 QGC 的能力（任务规划、飞行视图、飞行器设置、参数调优、多机监控、MAVLink 工具等）全部保留，在此基础上扩展了水质参数仪遥测与水质数据分析能力。

## 相比原版新增的功能

### 一、水质参数仪（实时遥测）

| 模块 | 说明 |
|---|---|
| MAVLink 遥测 | 新增 `VehicleWaterQualityFactGroup`，解析标准消息 `NAMED_VALUE_FLOAT`（msgid 251），支持 7 个参数：电导率 `COND`、酸碱度 `PH`、溶解氧 `DO`、铵离子 `NH4`、叶绿素 `CHLOR`、藻蓝蛋白 `TALPC`、浊度 `TURB`（电导率单位 mS/cm） |
| 工具栏指示器 | 位于卫星图标左侧，显示「电导率 / pH」双行实时数值；点击弹出 7 项参数表（含传感器类型与单位） |
| 水质图标 | 新增符合 QGC 图标规范的图标（透明背景、纯白单色、仅使用 `viewBox`） |

### 二、水质数据分析（新增）

| 能力 | 说明 |
|---|---|
| 数据导入 | 支持 `.xlsx` / `.csv`；**按表头别名自适应识别列**（中英文列名都认，如「电导率 / Conductivity / EC」），自动定位表头行（模板前几行是标题也能识别），无关列（温度、水深、COD、硝氮等）自动忽略 |
| 折线图 | **单参数**显示，导入后默认第一个参数，可下拉切换；按绘图区像素宽度降采样，支持滚轮缩放与悬停取值 |
| 地图热力路径 | 按文件中的**经纬度**拼出任务路径，再按所选参数的数值给每一段着色（蓝→红热力色带），配色带图例；无经纬度列或时间范围内采样点不足时给出明确提示 |

### 三、中英双语

- 新增界面一律采用「**英文源串 + 中文翻译**」写法：中文语言显示中文，英文语言显示英文
- 覆盖水质参数仪、水质分析页、地图图例与各类提示文案

## 构建

构建 / 测试 / 代码检查命令与编码规范见 [AGENTS.md](AGENTS.md)，架构模式与贡献流程见 [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md)。

## 开源协议

本项目继承上游 QGC 的开源协议，详见 [COPYING.md](.github/COPYING.md)。

## 相关链接

- [QGC 官方网站](http://qgroundcontrol.com)
- [用户手册](https://docs.qgroundcontrol.com/en/)
- [开发者指南](https://dev.qgroundcontrol.com/en/) / [构建说明](https://dev.qgroundcontrol.com/en/getting_started/)
- [讨论与支持](https://docs.qgroundcontrol.com/en/Support/Support.html)
- [上游仓库](https://github.com/mavlink/QGroundControl)


