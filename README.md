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
| 实时曲线 | 飞行界面**左下角的黑白水滴图标**，点击弹出实时折线图：默认 7 个参数各一色，可下拉只看单个参数；每秒采样一次、在内存里保留最近 10 分钟，支持清空重来 |

### 二、水质数据分析（新增）

| 能力 | 说明 |
|---|---|
| 数据导入 | 支持 `.xlsx` / `.csv`；**按表头别名自适应识别列**（中英文列名都认，如「电导率 / Conductivity / EC」），自动定位表头行（模板前几行是标题也能识别），无关列（温度、水深、COD、硝氮等）自动忽略 |
| 折线图 | **单参数**显示，导入后默认第一个参数，可下拉切换；按绘图区像素宽度降采样，支持滚轮缩放与悬停取值 |
| 地图热力路径 | 按文件中的**经纬度**拼出任务路径，再按所选参数的数值给每一段着色（蓝→红热力色带），配色带图例；无经纬度列或时间范围内采样点不足时给出明确提示 |
| 极值剔除 | 导入时**自动剔除每个参数的最大值与最小值**（可在页面上关掉）：折线图、地图热力路径、悬停取值与统计范围都按剔除后的数据计算，采样毛刺不会再把曲线和量程拉偏 |

### 三、中英双语

- 新增界面一律采用「**英文源串 + 中文翻译**」写法：中文语言显示中文，英文语言显示英文
- 覆盖水质参数仪、水质分析页、地图图例与各类提示文案

### 四、已实现的其它需求

| 编号 | 需求 | 状态 |
|---|---|---|
| 一 | 自动规划路线可设置循环次数，需要保存历史任务，可调用历史任务 | ✅ |
| 二 | 需要搭载三台雷达 | ✅ |
| 三 | 集成器客户端显示以及本地保存数据，遥控器端可下载水质数据 | ✅ |
| 四 | 可搭载二个网络摄像头 | ✅ |
| 五 | 关于水质数据的显示单独做一个界面实时显示出来，可以隐藏 | ✅ |
| 六 | 水质数据保存跟任务走，轨迹热力图同理 | ✅ |
| 七 | 采样支持自动采样，跟随任务航点，可选采样容量，采样后生成报告 | ✅ |
| 八 | 软件需要改一下 Logo，将「起飞」改成「自动航行」，软件名称改成 USV（澄峰科技） | ✅ |
| 九 | 创建一个任务打采样点，防止同一点位被重复勾选 | ✅ |
| 十 | 采样容量配置后台：按瓶子规格定量选择采样量 | ✅ |
| 十一 | 监测点位调整功能：无人船运行中遇到障碍物，可点击跳转，直接从 3 号点位开往 5 号点位 | ✅ |
| 十二 | 水质数据折线图，给图参考 | ✅ |
| 十三 | 航点勾选了采样以后需要有颜色变化，让用户直观看到该点已被勾选采样 | ✅ |
| 十四 | 电脑端和遥控器端同步处理，风格一致 | ✅ |
| 十五 | 支持数据导入生成折线图和热力图，便于剔除异常值查看 | ✅ |
| 十六 | 支持数据筛选不参与显示，比如极大值和极小值 | ✅ |
| 十七 | 集成测深仪传感器数据 | ✅ |
| 十八 | 集成喊话器 | ✅ |
| 十九 | 限速功能：手动状态下用旋钮调整最大速度输出，轻旋 5%，长旋连续变化 | ✅ |
| 二十 | 航线界面的调整 | ✅ |

### 五、双摄像头

| 能力 | 说明 |
|---|---|
| 双视频源 | 视频设置里可选**视频一来源**与**视频二来源**，各自独立配置 RTSP / UDP(H264/H265/MPEGTS) / TCP 地址；来源下拉同时充当开关，选「Disabled」即不加载 |
| 主辅画面 | 主摄像头铺满，辅摄像头显示在右下角小窗；点「⇌」按钮切换主辅，按钮贴在辅画面左上角避开角标，窗口过小或非全屏时隐藏 |
| 容错 | 任一路连续启动失败 3 次即放弃并给出警告，不再反复重试；RTSP 地址允许省略 `rtsp://` 前缀；空地址不启动管线 |
| 稳定性 | 修复 GStreamer 启动失败后的 SEH 崩溃（管线销毁后仍被重连路径解引用） |

### 六、水质采样

| 能力 | 说明 |
|---|---|
| 航点采样设置 | 航点编辑器新增「采样」页（相机图标左边），默认页；整条航线只允许一个采样点，勾选新的会把旧的取消 |
| 停留时间 | 采样停留时间写入 `NAV_WAYPOINT` 的 param1，飞行界面显示实时进度 |
| 固件驱动 | 采样流程由飞控 `STATUSTEXT` 驱动（选瓶 → 下放 → 抽水 → 静置 → 收杆 → 完成），舵机指令经 `MAV_CMD_DO_SET_SERVO` 串行下发；2 秒内飞控未确认启动即回滚并提示 |
| 参数可读 | 读取 `WS_MAX_VOLUME` / `WS_FLOW_RATE` / `WS_OPEN_TIME` / `WS_CLOSE_DELAY` / `WS_CLOSE_TIME` / `WS_TRIG_CHAN` / `WS_BOTTLE_CHAN` / `WS_VOLUME_CHAN` |
| 容量选择 | 按船配瓶子容量定量选择采样量 |

### 七、飞行界面（无人船定制）

| 能力 | 说明 |
|---|---|
| 模式菜单 | 只保留手动 / 自动 / 返航 / 悬停 4 个模式，中文显示、下发仍用固件原始模式名 |
| 任务剩余时间 | 右下角遥测条显示任务剩余 `HH:MM:SS`，按用户设置的**真实自主导航速度**预算；随船体移动连续递减，到终点归零 |
| 下一航点距离 | 显示到下一个航点的真实距离（米，一位小数） |
| 自主导航速度 | 航线界面工具条「着陆」与「统计」之间新增**速度**按钮，点开向右展开面板填入速度（上限 5 m/s），确定前弹确认框；确认后写入任务所有航点并随任务上传，船按此速度航行 |
| 图标卡片 | 水质/采样入口为方形卡片竖排贴在摄像头小窗上方，随小窗缩放与全屏跟随，不被遮挡 |

### 八、航线界面裁剪（无人船专用）

隐藏高度相关项（航线统计的高度差、选中航点与默认值里的航点高度、地形剖面图），隐藏电子围栏 / 集结点 / 变换分组，飞行器信息固定显示「无人船」并去掉预期返航位置。

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


