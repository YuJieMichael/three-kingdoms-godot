# Godot 验证记录

## 0.2.0 城池经营更新

2026-10-06，Godot `4.7.2.stable.official.ed1daf0bf`，标准版 GDScript。0.2.0 本地检查、实际网页经营验证与 macOS 原生面板观察已通过；Windows/Web 包已发布，正式 Windows 导出包 headless 启动 CI 通过。以下 0.1.1 的 CI 链接属于历史版本，本次运行证据单独记录。

### 自动检查

| 范围 | 通过数量 | 本轮重点 |
| --- | ---: | --- |
| 真实 HTTP 桥接 | 22 | 满仓交易、黄金与交易上限、税率与忙碌城守、招募费用及两类俘将占位、多城经营范围、跨重启回执 |
| 原生地图 | 24 | 继续验证相机、拖动/缩放、隐藏任务据点和行军语义 |
| 城池/战斗表现 | 31 | 继续验证建筑、军令与回合表现、窄屏日志布局 |
| 客户端 | 71 | 继续验证布局、地图状态保持、命令顺序、持久未确认请求与重连 |
| 原生城池事务 | 79 | 市场数量实时预览和提交、城守/税率、客栈、等待回执与刷新、电脑/窄屏和事务奖励换行 |
| **总计** | **227** | 根代理独立执行并确认通过 |

Godot 导入通过；构建脚本在导入前生成 `build/.gdignore`，避免递归导入此前导出的资源。CCGS 按 minimal 工作流显式执行验证；本地辅助资料未启用 hook 或 watcher，且不进入 Git 提交或导出包。

### 实际网页观察

IAB 浏览器实际加载 Godot WebAssembly 客户端，在 1280×720 / DPR 2 与 390×844 / DPR 1 完成三类经营界面和事务入口操作。这是浏览器窄屏验证，尚未进行真实 iPhone Safari 或多点触控测试。

使用独立合法虚构存档设置市场 2 级、客栈 2 级、招贤馆 4 级与民房 2 级。观察并经权威快照核对：

- 满仓粮草 10000 / 上限 10000，黄金 50005。输入 `999999` 时，实时成交预览和提交数量收敛到 50005；买入后粮草 60005、黄金 0，资源完整超仓入库。随后卖出 10000，粮草 50005、黄金 10000。操作后面板更新实际余额。
- 客栈打听不扣黄金，显示徐晏（3 级、3000 黄金）和夏松（2 级、2000 黄金）。招募徐晏后黄金 7000、已用房间 3 / 4、将领列表 3 人，属性来自原规则。
- 任命林朔为城守，面板显示城外生产和建设系数 1.48；税率调整为 30%，民心目标 70、显示黄金收入 0.84 / 分钟。
- 后端快照 revision 7 确认上述交易、招募、任命与税率已保存。重新加载后仍显示同一进度（粮草 5.0 万、黄金 7009；期间正常时间收入继续结算）。
- 窄屏市场、城守/税率、客栈均可滚动操作；事务菜单完整容纳入口，任务描述与奖励换行。浏览器 error/warn 日志为空。

截图保留于 `docs/screenshots/management-*.jpg`，包括电脑与窄屏三类表单、事务菜单、城池和将领表。本轮测试没有读取或覆盖玩家原网页存档，`.local/play` 新城进度保持独立；虚构经营存档仅验证操作与规则衔接，不作为自然成长节奏或经济平衡结论。

### 构建与桌面运行边界

官方 Windows 与 Web 模板均导出成功，包内包含 Node Windows 24.21.0、规则服务、游戏资源与许可证，规则快照保持 `c7674df45b9595405e57907524e737e633b0ff63`。本次产物清单：

| 文件 | 字节数 | SHA256 |
| --- | ---: | --- |
| ThreeKingdoms-Godot-v0.2.0-Windows-x64.zip | 86844832 | `d479679ea49c4e15ba17ddce66a97c591116e216853fd6109df99f81eb1df3ff` |
| ThreeKingdoms-Godot-v0.2.0-Web-preview.zip | 59004695 | `f4175dd8d0d24de44a9db50d7636c1118b85556533df35fc66d637bcb653b8cc` |

`build/build-manifest.json` 与 `SHA256SUMS.txt` 同时生成。canonical runtime hash 仍为 `432f9fea6359c18a8d1e2655b09f97770718c3e676501c602c7897afd906a8b4`，原网页仓库 HEAD 不变、工作区干净，没有修改或部署原 Pages。

本机非 headless Godot 客户端已启动，日志确认 OpenGL / Apple M1 和本地规则服务就绪，未出现脚本错误。macOS 原生桌面窗口已实际观察：城池场景与经营入口可见，市场、城守/税率和客栈三个面板均只读打开检查，未执行交易或更改桌面存档；原生截图保留为 `docs/screenshots/management-city-native.jpg`。导出成功、headless 启动、人工桌面交互试玩和长期体验分别记录。

### 0.2.0 发布与 Windows 实际启动

[v0.2.0 预览发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.2.0) 源码与标签均指向 `aa963a8d7584103595983896d8681d2b59e8bfc1`。GitHub 上两个 ZIP、`build-manifest.json` 与 `SHA256SUMS.txt` 四个资产的 digest 均与本地产物一致。

[Windows CI 运行](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37467149603) 在同一提交完成并全绿：真实桥接检查、Godot 导入与原生脚本检查、源码客户端启动以及 `Verify exported Windows executable` 均 success，CI 亦确认上述 227 项全部通过。发布包步骤从正式发布下载 Windows ZIP，核对 SHA256，解压后直接运行 `ThreeKingdoms.exe --headless -- --smoke`，连接随包本地规则服务，收到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`。这确认正式导出包可以启动并载入权威状态与地图，不等于 Windows 人工长局或 Steam 成品验证。

Steamworks、公开账号/共享世界、百人压力测试、真实手机触控、Windows 人工长局、控制器与 Steam Deck 均未验证。原游戏完整名将/招降、联盟、计谋、其它城池管理及正式美术继续迁移；PC 开发后续顺序见 [PC 工作流](PC-GAMES.zh.md)。

### 本地图谱

沿用 `extract . --code-only --exclude '.claude/**' --exclude 'docs/engine-reference/**'`，再 `cluster-only . --no-label`。本轮刷新后为 553 节点、1662 边、29 社区。没有外部语义提取、上传、watcher 或 hooks。Graphify 0.9.76 未识别 `.gd`，引擎 IIFE 覆盖亦不完整；原生界面关系继续核对源码和真实 SceneTree，图中缺少节点不代表没有依赖。

![0.2.0 电脑市场与满仓入库预览](screenshots/management-market-desktop.jpg)

![0.2.0 手机市场](screenshots/management-market-mobile.jpg)

![0.2.0 手机城守与税率](screenshots/management-governance-mobile.jpg)

![0.2.0 手机客栈招募](screenshots/management-inn-mobile.jpg)

![0.2.0 手机事务入口与奖励换行](screenshots/management-transactions-mobile.jpg)

![0.2.0 macOS 原生桌面城池与经营入口](screenshots/management-city-native.jpg)

## 0.1.1 历史验证记录

2026-10-06，Godot `4.7.2.stable.official.ed1daf0bf`，标准版 GDScript。

0.1.1 修正变量字体的整数轴标签，实际渲染坐标确认字重 500；新增直接读取 TextServer 字体坐标的回归检查。初版建设/行军/战斗链路截图保留，当前新城与手机截图已更新为 0.1.1。

### 已完成

- 原仓库 HEAD `c7674df45b9595405e57907524e737e633b0ff63`，工作区干净；没有修改或部署原 GitHub Pages。
- 15 个真实 HTTP 桥接集成用例通过：CAS 并发、重复编号回执跨重启、只读时间投影不重复结算、建筑/训练/真实混编行军、战斗胜利及一次结算、随机加速不重抽、存档迁移/损坏保护、Origin/token/文件隔离。
- 24 个地图检查通过：屏幕/世界坐标、相机边界、拖动阈值、锚点缩放、触屏手势、分区配置、隐藏未来任务据点、行军/驻扎时间语义。
- 31 个城池/战斗表现检查通过：实际建筑等级、军令转发、回合事件动画、旧回合不重复播放、真实主题下窄屏双列按钮不重叠、日志布局。
- 71 个客户端检查通过：1280 与 390 宽度、1280×720 的高度/页脚/侧栏滚动、手机军队末尾按钮可达、资源更新保持地图实例和视角、战斗命令依次使用新 revision 与 sourceCity、持久 pending、同 authority 原编号重试、另一存档禁止重放、401 与请求在途重连、成功清回执、409 刷新。
- macOS 实际运行 Godot 场景并连接自动启动的本地规则服务，收到 `GODOT_SMOKE_OK`，4096 个地图格来自原规则。
- 官方 Windows 与 Web 模板导出成功；打包包含 Node Windows 24.21.0、规则服务、完整资源、许可证和校验清单。下载工具先验证官方 SHA512/SHA256。
- 实际 IAB 浏览器运行 WebAssembly 原生客户端；1280×720 / DPR 2 与 390×844 / DPR 1 验证。修复 Web 高分屏逻辑尺寸、较矮窗口侧栏溢出和手机军队入口不可达。点选、拖动、滚轮缩放、礼包领取、民房建设、配兵出征与真实到达倒计时已操作。战场重新加载恢复，连续两回合战斗胜利自动结算；战报确认损失弓箭兵 2、幸存 998、实际入库粮草 429 / 木材 117，以及俘虏士兵。控制台未出现脚本错误。

### 发布验证

Windows GitHub Actions 源码验证通过：[运行记录](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37421609588)。从本次发布下载 Windows ZIP、核对 SHA256、解压、直接启动导出的 `ThreeKingdoms.exe --headless -- --smoke`，实际运行成功并连接随包规则服务，收到 `GODOT_SMOKE_OK`：[发布包运行记录](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37421796832)。导出成功和 headless 启动不等于 Windows 桌面交互试玩已完成。

### 测试边界

浏览器战斗使用本仓库 `.local/qa-web` 的虚构进度：校场与弓兵由合法测试存档导入，用于检查 UI→规则→战场→战报链路，不作为新手成长速度或资源平衡结论。没有读取、导入或覆盖玩家原网页存档。

尚未进行真实 iPhone Safari 多点触控、Steamworks、百人压力测试、公网账号/共享世界部署或自然长局平衡测试。程序绘制美术为迁移试玩资源，原游戏其它界面仍需继续迁移。

### 本地图谱

沿用 `extract . --code-only --exclude '.claude/**' --exclude 'docs/engine-reference/**'`，再 `cluster-only . --no-label`。553 节点、1667 边、32 社区，无外部语义提取、上传、watcher 或 hooks。

Graphify 0.9.76 当前未识别 GDScript `.gd`；生成的图主要覆盖规则快照与 Node 桥接，原引擎 IIFE 内部仍覆盖不足。Godot 场景关系以 `scenes/main.tscn` 与 `src/*.gd` 源码、真实 SceneTree 验证为准，图中不存在节点不代表没有依赖。

![实际地图拖动和缩放](screenshots/map-desktop.jpg)

![手机战斗布局与恢复](screenshots/battle-mobile.jpg)

![实际战损和入库战报](screenshots/report-mobile.jpg)

![0.1.1 新城预览](screenshots/new-city-preview.jpg)

![0.1.1 手机字体和布局](screenshots/new-city-mobile.jpg)
