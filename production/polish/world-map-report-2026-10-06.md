# 大地图性能报告

Generated: 2026-10-06
Scope: 独立 Godot 客户端的大地图绘制与行军路线。
Status: COMPLETE — 本机同条件性能比较已完成；故事 004 的实际导出观察、发布资产校验及正式 Windows 包运行 CI 已完成，故事状态为 DONE。
Workflow: CCGS `perf-profile`，配置 `performance.enforce: warn (default)`。

## 结果与证据

最终捕获中，四个动态场景的每次重绘 CPU 均值及 p95 均低于原基线，其中合成 256² 总览收益最大。这仅说明当前开发机、相同插桩基准中的绘制命令准备减少：`64_pan` 的帧间隔 p95 略升，CANVAS draw calls 没有下降，世界快照准备与行军扫描增加了成本；没有全面 FPS、GPU 或目标平台达标结论。

| 输入 | 状态 | 证据 |
|---|---|---|
| 地图、API 与 DTO 源码 | FOUND | 补查 `.gd` 与桥接，确认绘图和规则边界 |
| AGENTS、项目配置与故事 | FOUND | 保留 canonical 64² 世界、存档与平台范围 |
| 原生基准脚本 | FOUND | 固定 seed、摄像机路径、视口及插桩 |
| 优化前原生 JSON | FOUND | [before](data/map-before-2026-10-06.json)，总捕获与五场景均 `valid=true` |
| 第一轮原生 JSON／比较 | FOUND | [first after](data/map-after-first-2026-10-06.json)、[first comparison](data/map-comparison-first-2026-10-06.json)，保留回退审计 |
| 最终原生 JSON／比较 | FOUND | [final after](data/map-after-2026-10-06.json)、[final comparison](data/map-comparison-2026-10-06.json)，`matched=true` |
| GPU 时间 | ABSENT | UNAVAILABLE / NOT ASSESSED — NO DATA |
| Windows/Web 性能采样 | ABSENT | NOT ASSESSED — NO DATA；启动或视觉观察不代替计时 |
| OS RSS 与独立加载时间 | ABSENT | NOT ASSESSED — NO DATA |

Graphify 查询确认 `worldView()` → `marchesView()` 等桥接关系；当前图谱不识别 `.gd`，地图结论由源码补查与运行数据取得，没有以图谱缺失证明没有依赖。

## 预算

使用项目 `.claude/hooks/yaml-helper.sh resolve_config` 解析有效配置；四项共享预算均未设定，设计材料也未给出已约定数值。默认 enforce 为 warn，本轮不更改配置，不使用技能模板中的 60 FPS、16.67 ms 或调用上限判断通过。

| 指标／配置键 | 已提交预算 | 本轮数据 | 预算状态 |
|---|---|---|---|
| 帧率 `performance.target_framerate` | 未设定 | 没有独立 FPS profiler；帧间隔单列 | NOT ASSESSED — NO BUDGET |
| 帧耗时 `performance.frame_budget_ms` | 未设定 | 有 CPU draw 与帧间隔；没有完整 CPU/GPU 帧分解 | NOT ASSESSED — NO BUDGET |
| 绘制调用 `performance.draw_call_limit` | 未设定 | CANVAS counters 已采集 | NOT ASSESSED — NO BUDGET |
| 内存 `performance.memory_ceiling_mb` | 未设定 | 引擎 static memory 已采；RSS 未采 | NOT ASSESSED — NO BUDGET |
| 加载时间 | 未设定 | 未采独立启动／读档耗时 | NOT ASSESSED — NO DATA / NO BUDGET |

未设预算不等于零或达标，没有可计算的预算余量。基准限帧 60 是控制实验条件，不是项目目标。

## 环境、源码与测量口径

三次捕获均为 Apple M1 / 8 核，macOS 27.0.1，Godot 4.7.2 stable official debug；`gl_compatibility` / `opengl3`，视频 API `4.1 Metal - 91.7`，显示器 60 Hz、scale 2。窗口与逻辑视口均为 1280×800，VSync mode 1、限帧 60，每场景热身 30、采样 150 帧，seed 439903。

| 捕获 | UTC 时间 | 地图源码 SHA256 |
|---|---|---|
| before | 13:54:56–13:56:13 | `6fde79b3ad1a42a292297288dabb535a61ac1eb5edd21f9c4cfac6238682e3ea` |
| first after | 14:05:48–14:07:00 | `759e68ae86e30493f6f0c40c7f20b8833cc09fc57709dc6e935462576e12b425` |
| final after | 14:15:43–14:16:52 | `4d0fbb443343438e77d6a9b9194a019dec0562fb0c88b0d0673cf0c21cc90179` |

三次基准 SHA256 均为 `0222249719b1845686dc012adbbb1b62aa9f054f6110593ea04e60fd7542d461`。源码、基准及视口在各次运行期间未变；两份 comparison 的环境、参数、fixture hash 和逐帧摄像机路径均匹配，原始分位数与每帧数据完整保留。每种实现只有一次短捕获，不能证明长期稳定性或因果隔离每项微优化。

- `draw_cpu_ms` 是 GDScript 构造绘制命令的 CPU 时间，含测量代码开销，不是 GPU 时间、完整帧耗时或 FPS。
- 分层时间属于 CPU draw，总绘制与分层不能重复相加；每次重绘与每采样帧统计分别标注。
- `frame_interval_ms` 包含 VSync、限帧、渲染和系统调度，不测输入延迟，不能用 `1000 / draw_cpu_ms` 倒推游戏 FPS。
- `canvas_draw_calls` 为视口 CANVAS 引擎计数，tile/route calls 是脚本次数。
- `MEMORY_STATIC` / `MEMORY_STATIC_MAX` 是整个 debug Godot 进程的引擎内存监视，不是地图独占内存或 OS RSS。后序场景峰值会继承早前分配。
- `set_world_cpu_ms` 为合成 DTO 的单次复制和索引准备，不是完整游戏加载或网络下载；每场景只有一个快照，不作稳定增幅推断。

## 最终 CPU 绘制比较

单位 ms；除静态初次绘制外，列的是 `summary_per_redraw`。

| 场景 | before 均值／p95 | final 均值／p95 | p95 本次减少 | 150 个采样帧的重绘数 before→final |
|---|---:|---:|---:|---:|
| `64_static`：64²，80%，无行军 | 无采样重绘；初次 41.329 | 无采样重绘；初次 40.259 | 不评估空重绘统计 | 0→0 |
| `64_pan`：64²，80%，无行军 | 16.010／17.543 | 15.147／16.626 | 5.2% | 150→150 |
| `256_overview_pan`：合成 256²，17% | 67.206／72.376 | 34.291／37.163 | 48.7% | 150→150 |
| `256_marches_pan`：合成 256²，80%，200 行军 | 18.792／22.133 | 16.281／19.645 | 11.2% | 300→300 |
| `256_marches_idle`：合成 256²，80%，200 行军 | 21.267／23.175 | 17.516／18.710 | 19.3% | 150→150 |

`256_marches_pan` 每采样帧仍发生两次重绘，其每帧 CPU 均值 37.584→32.562、p95 43.986→39.144 ms，与上表单次重绘不同。CPU 少了不代表重绘数量减少；本轮没有合并摄像机与行军导致的绘制，也没有拆动态 Canvas 层。静态场景热身后空重绘统计的 count=0、分位数=null，不描述为首次绘图免费。

各场景实际采样持续时间 before→final 为 2.499→2.508、9.247→9.090、22.776→17.820、15.480→14.886、11.417→10.385 秒；150 帧并非固定 2.5 秒。

## 帧间隔、调用、内存与快照代价

| 场景 | 帧间隔 p95 ms，before→final | CANVAS calls 每帧均值，before=final | 引擎 static memory 均值 MiB，before→final | 单次 set_world ms，before→final |
|---|---:|---:|---:|---:|
| `64_static` | 18.033→18.096 | 3795 | 61.720→61.824 | 5.590→8.020 |
| `64_pan` | 67.432→67.678 | 3380.220 | 62.084→62.197 | 4.980→7.510 |
| `256_overview_pan` | 166.077→131.658 | 7930.900 | 231.557→231.632 | 81.972→122.493 |
| `256_marches_pan` | 125.707→122.601 | 3510.260 | 232.428→232.557 | 80.117→133.908 |
| `256_marches_idle` | 83.001→75.359 | 3837 | 232.565→232.680 | 86.845→123.185 |

`64_pan` 帧间隔 p95 上升 0.246 ms，静态场景也略升；不能说所有帧指标改善。CANVAS calls 的均值、p95 和原始序列未下降，几何保持不变且本轮没有绘制调用批处理。新索引、到达监控与缓存带来额外状态：单次 set_world 各组均更高，需要后续评估定期世界快照刷新是否造成可感的卡顿。引擎内存均值略增，表中 MiB 使用 1024² 字节换算；这是整个 debug 进程与 DTO，不宣称地图内存下降。

行军扫描也增加 CPU：`256_marches_pan` 每帧 process 均值 0.005→0.057 ms，idle 0.011→0.101 ms；新逻辑多检查可见性与一次性到达边沿。当前重场景 total draw CPU 降低，但这些新增成本不能隐藏。此处没有真实规则服务的网络、JSON、存档或结算计时。

## 热点与本轮处理

| 热点／负责人 | before→final 的每次重绘实测均值 | 本轮处理及边界 |
|---|---|---|
| 总览地形／地图负责人 | landform 39.028→32.932 ms | 复用局部像素尺寸，terrain match；不改颜色、阴影或形状 |
| 总览特征／地图负责人 | tile features 20.669→0.527 ms；calls 9845.467→35.087 | 稀疏城池／任务／主城索引保持原顺序与 43%/46% 阈值；大图快照索引增加成本 |
| 正常特征／地图负责人 | 64_pan features 13.143→12.767 ms | 缓存纯坐标的森林偏移与山峰归一化 shift，复用颜色常量；每类上限 2048，整体清空策略未测长局尾部 |
| 河流准备／地图负责人 | 200 pan rivers 1.282→0.163 ms | 按可见 world x/y 裁剪原采样格、保留邻点与原宽度 |
| 行军绘制／地图负责人 | 200 pan marches 1.778→1.179 ms | 裁剪长虚线且保留原始相位；可见性筛选和完成刷新有新增 process 代价 |

上述是同一基准整体实现的分层观察，不能把全部差异因果分配给单个 cache、match 或常量。源码确定的 600 段／9000 px 路线缺失已修复；功能正确性与 CPU 收益分别记录。回归检查覆盖屏外穿屏、反向与两百万像素线、相位、驻扎／采集、筛选、可见连续动画、首次扫描前到达、卡顿跨越到达及单次最终刷新。缓存只保存纯坐标几何，不保存 terrain、ownership、camera 或 zoom；山峰乘法顺序调整存在极小浮点舍入差异，没有意图修改山体形状。

## 第一轮回退审计

第一轮捕获有效且 matched，但其部分 CPU 尾部回退，未将该版当作全面改善完成。随后加入有界纯几何缓存、颜色常量及特征 terrain match，再取得独立 final 捕获。保留 first after 和 first comparison，不覆盖慢结果或从两版中挑选最佳场景拼成报告。

| 指标 | before | first after | final after |
|---|---:|---:|---:|
| 64_pan 每次重绘 CPU p95 | 17.543 | 19.729 | 16.626 |
| 总览每次重绘 CPU p95 | 72.376 | 46.527 | 37.163 |
| 200 pan 每采样帧 CPU p95 | 43.986 | 50.724 | 39.144 |
| 200 idle 每次重绘 CPU p95 | 23.175 | 25.263 | 18.710 |

## 剩余事项与建议

- 后续由地图负责人评估动态 Canvas 分层或帧内合并重绘；当前 200 pan 仍是 300 redraw/150 samples，不把分层描述为已实现。
- 对全图漫游及定期世界快照刷新作长局 capture，检查 2048 容量整体 eviction 与 set_world 的尾部；本轮仅短捕获。
- 当前标记／标签沿用左右 120、上下 35 px 可见 margin；极长名称应另行按实际字体边界求交，本轮未修复该旧限制。
- GPU timing、RSS、Windows/Web/真实手机性能、持续长局、输入延迟和多人压力为 NOT ASSESSED — NO DATA。预算符合性均为 NOT ASSESSED — NO BUDGET。
- 合成 256² 不改变 canonical 64²，200 条行军不等于 200 名玩家、联网能力或已实现扩州。

Verdict: COMPLETE — 性能报告与有效原始比较已保存，最终 CPU 绘制收益及实际回退／额外代价均已记录；预算符合性、缺失平台及 GPU 数据仍为 NOT ASSESSED。故事 004 已完成实际导出观察、发布资产校验及 [正式 Windows 包运行 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479418934)，八项验收全部 DONE；启动证据不扩大本报告的平台性能测量范围。复现见 [地图性能说明](../../docs/MAP-PERFORMANCE.zh.md)。
