# Godot 0.1.0 验证记录

2026-10-06，Godot `4.7.2.stable.official.ed1daf0bf`，标准版 GDScript。

## 已完成

- 原仓库 HEAD `c7674df45b9595405e57907524e737e633b0ff63`，工作区干净；没有修改或部署原 GitHub Pages。
- 15 个真实 HTTP 桥接集成用例通过：CAS 并发、重复编号回执跨重启、只读时间投影不重复结算、建筑/训练/真实混编行军、战斗胜利及一次结算、随机加速不重抽、存档迁移/损坏保护、Origin/token/文件隔离。
- 24 个地图检查通过：屏幕/世界坐标、相机边界、拖动阈值、锚点缩放、触屏手势、分区配置、隐藏未来任务据点、行军/驻扎时间语义。
- 31 个城池/战斗表现检查通过：实际建筑等级、军令转发、回合事件动画、旧回合不重复播放、真实主题下窄屏双列按钮不重叠、日志布局。
- 70 个客户端检查通过：1280 与 390 宽度、1280×720 的高度/页脚/侧栏滚动、手机军队末尾按钮可达、资源更新保持地图实例和视角、战斗命令依次使用新 revision 与 sourceCity、持久 pending、同 authority 原编号重试、另一存档禁止重放、401 与请求在途重连、成功清回执、409 刷新。
- macOS 实际运行 Godot 场景并连接自动启动的本地规则服务，收到 `GODOT_SMOKE_OK`，4096 个地图格来自原规则。
- 官方 Windows 与 Web 模板导出成功；打包包含 Node Windows 24.21.0、规则服务、完整资源、许可证和校验清单。下载工具先验证官方 SHA512/SHA256。
- 实际 IAB 浏览器运行 WebAssembly 原生客户端；1280×720 / DPR 2 与 390×844 / DPR 1 验证。修复 Web 高分屏逻辑尺寸、较矮窗口侧栏溢出和手机军队入口不可达。点选、拖动、滚轮缩放、礼包领取、民房建设、配兵出征与真实到达倒计时已操作。战场重新加载恢复，连续两回合战斗胜利自动结算；战报确认损失弓箭兵 2、幸存 998、实际入库粮草 429 / 木材 117，以及俘虏士兵。控制台未出现脚本错误。

## 发布验证

Windows GitHub Actions 源码验证通过：[运行记录](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37420521752)。从本次发布下载 Windows ZIP、核对 SHA256、解压、直接启动导出的 `ThreeKingdoms.exe --headless -- --smoke`，实际运行成功并连接随包规则服务，收到 `GODOT_SMOKE_OK`：[发布包运行记录](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37420714887)。导出成功和 headless 启动不等于 Windows 桌面交互试玩已完成。

## 测试边界

浏览器战斗使用本仓库 `.local/qa-web` 的虚构进度：校场与弓兵由合法测试存档导入，用于检查 UI→规则→战场→战报链路，不作为新手成长速度或资源平衡结论。没有读取、导入或覆盖玩家原网页存档。

尚未进行真实 iPhone Safari 多点触控、Steamworks、百人压力测试、公网账号/共享世界部署或自然长局平衡测试。程序绘制美术为迁移试玩资源，原游戏其它界面仍需继续迁移。

## 本地图谱

沿用 `extract . --code-only --exclude '.claude/**' --exclude 'docs/engine-reference/**'`，再 `cluster-only . --no-label`。553 节点、1667 边、32 社区，无外部语义提取、上传、watcher 或 hooks。

Graphify 0.9.76 当前未识别 GDScript `.gd`；生成的图主要覆盖规则快照与 Node 桥接，原引擎 IIFE 内部仍覆盖不足。Godot 场景关系以 `scenes/main.tscn` 与 `src/*.gd` 源码、真实 SceneTree 验证为准，图中不存在节点不代表没有依赖。

![实际地图拖动和缩放](screenshots/map-desktop.jpg)

![手机战斗布局与恢复](screenshots/battle-mobile.jpg)

![实际战损和入库战报](screenshots/report-mobile.jpg)
