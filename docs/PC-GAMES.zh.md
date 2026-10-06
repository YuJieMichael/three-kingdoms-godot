# PC 游戏开发工作流

用户指定 `game-development/pc-games`，本轮已安装、读取并采用该工作流。它是一组 Codex 开发指引，没有独立的启动程序。当前启动对象仍是本项目的 Godot 客户端及本地规则服务；安装技能不会自动启用 watcher、hook、外部服务或 Steam SDK。

## 来源与安装

来源：[sickn33/agentic-awesome-skills](https://github.com/sickn33/agentic-awesome-skills/tree/b6ceca367a3b3ee90a273a3afa895960e8e9d7a5/skills/game-development)，固定提交 `b6ceca367a3b3ee90a273a3afa895960e8e9d7a5`，由用户提供的 Skillselion 页面链接核实。使用 Codex `skill-installer` 的 GitHub 安装脚本安装父目录，包含嵌套的 `pc-games`，无需再次安装。

- 入口：`/Users/lihuazeng/.codex/skills/game-development/SKILL.md`
- 已选路线：`/Users/lihuazeng/.codex/skills/game-development/pc-games/SKILL.md`

安装的 12 个 Markdown 文件逐一与该提交的 Git blob 哈希核对一致，未包含可执行文件。后续对话可自动发现这些技能，本轮已直接读取指引。

## 应用于现有客户端

目标保持 Windows 桌面试玩、后续 Steam 发布与 Web 导出。继续使用 Godot 4.7.2＋GDScript；状态、地图与命令完成等 Signals 将界面和 API 连接解耦。玩家操作经过 `game_api.gd` 的命令入口、版本检查与未确认请求恢复，再由 Node 桥接调用原游戏的命令白名单。费用、资源、招募、行军和战斗仍在 canonical 规则中结算，客户端只呈现确认后的结果。安装技能不改变原网页版、规则快照或存档格式。

Windows 包包含游戏资源、规则服务和 Node 运行时；Web 包通过本机服务提供网页及同源 API。二者仍是本地试玩，没有 Steam 身份、云存档或公网玩家账号。更完整的合同见 [架构说明](ARCHITECTURE.zh.md)。

本轮 0.2.0 本地回归共 227 项通过：规则桥接 22 项、地图 24 项、城池与战斗表现 31 项、客户端 71 项、城池事务 79 项。macOS 原生城池与三类经营面板已只读打开观察；Windows CI 的源码导入、原生检查、客户端启动及正式发布包启动均通过。CI 下载 ZIP、核对 SHA256、解压并执行 `ThreeKingdoms.exe --headless -- --smoke`，收到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`：[运行记录](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37467149603)。Windows 导出、headless 启动、人工桌面试玩和长期游戏体验分别记录；Windows 人工长局、真实 iPhone 多点触控、控制器与 Steam Deck 尚未验证。

## 桌面端后续顺序

1. **补充可配置输入。** 为确认、取消、切换页面、回城定位、地图平移和缩放定义 InputMap 动作，允许键鼠重绑定并保存设置。保留现有鼠标与触摸操作，用真实键盘焦点、弹窗返回和滚动交互验证可用性，再扩展手柄映射。
2. **先建立性能基线。** 用 Godot Profiler 在约定窗口大小、地图缩放、行军数量及拖动路径下记录帧耗时、绘制开销和内存，再据结果调整可见范围、批量绘制或细节层级。当前没有测得可报告的 FPS 基线，不能以导出成功代替顺滑度验证。
3. **再接 Steam。** 确定 Steam App ID、接入方式与账号后端后，设计少量可验证的成就和云存档策略。云存档需明确进度归属、版本冲突及跨端恢复；公网多人进度由账号与服务器权威结算管理。排行榜、创意工坊和在线状态按玩法需求逐步加入。

每项功能继续在独立 Godot 仓库开发，使用真实规则与存档验证。技能中的通用引擎比较不覆盖项目已选目标，也不代替当前平台文档或实际运行测试。
