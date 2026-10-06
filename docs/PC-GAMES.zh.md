# PC 游戏开发工作流

用户指定 `game-development/pc-games`，已安装、读取并继续采用该工作流。它是一组 Codex 开发指引，没有独立的启动程序。当前启动对象仍是本项目的 Godot 客户端及本地规则服务；安装技能不会自动启用 watcher、hook、外部服务或 Steam SDK。

## 来源与安装

来源：[sickn33/agentic-awesome-skills](https://github.com/sickn33/agentic-awesome-skills/tree/b6ceca367a3b3ee90a273a3afa895960e8e9d7a5/skills/game-development)，固定提交 `b6ceca367a3b3ee90a273a3afa895960e8e9d7a5`，由用户提供的 Skillselion 页面链接核实。使用 Codex `skill-installer` 的 GitHub 安装脚本安装父目录，包含嵌套的 `pc-games`，无需再次安装。

- 入口：`/Users/lihuazeng/.codex/skills/game-development/SKILL.md`
- 已选路线：`/Users/lihuazeng/.codex/skills/game-development/pc-games/SKILL.md`

安装的 12 个 Markdown 文件逐一与该提交的 Git blob 哈希核对一致，未包含可执行文件。后续对话可自动发现这些技能，本轮已直接读取指引。

## 应用于现有客户端

目标保持 Windows 桌面试玩、后续 Steam 发布与 Web 导出。继续使用 Godot 4.7.2＋GDScript；状态、地图与命令完成等 Signals 将界面和 API 连接解耦。玩家操作经过 `game_api.gd` 的命令入口、版本检查与未确认请求恢复，再由 Node 桥接调用原游戏的命令白名单。费用、资源、招募、行军和战斗仍在 canonical 规则中结算，客户端只呈现确认后的结果。安装技能不改变原网页版、规则快照或存档格式。

Windows 包包含游戏资源、规则服务和 Node 运行时；Web 包通过本机服务提供网页及同源 API。二者仍是本地试玩，没有 Steam 身份、云存档或公网玩家账号。更完整的合同见 [架构说明](ARCHITECTURE.zh.md)。

0.3.0 将常用页面、事务、存档、按键设置及地图移动/缩放抽象为 InputMap 动作。默认 1–5 切换城池/大地图/军队/将领/战报，H / Home 回城，T 事务，O 存档，K 按键设置；WASD / 方向键移动地图，`=` / 小键盘 `+` 放大，`-` / 小键盘 `-` 缩小。设置中的每个动作可更改为一个按键组合，重复或保留键有明确反馈；Tab、Enter、Esc 继续由 Godot 原生控件处理。绑定保存至单独的 `user://input-settings.cfg`，失败不会更改当前有效映射，损坏配置完整回退默认。

0.3.0 原有 227 项及新增输入 255 项检查通过，共 482 项，覆盖持久化、失败回滚、配置损坏、真实输入事件、地图边界、同帧短按、反向键抵消、按钮焦点与文本/弹窗隔离、失去窗口焦点及窄屏设置布局。实际 macOS 原生窗口完成冲突拒绝、F9 重绑并重启生效、恢复默认、方向键移动、小键盘缩放与 H 回城。最终 Web 实际验证存档文字输入隔离、Esc 关闭后立即 2 切舆图、地图平移/缩放/回城、390×844 事务入口和设置滚动/恢复默认，浏览器 warn/error 日志为空。[0.3.0 Windows/Web 包](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.0) 已发布，四项资产 digest 与本地一致；[正式 Windows 包启动 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37472454474) 全绿，下载校验 ZIP 后执行导出客户端，收到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`。完整结果见 [验证记录](QA.zh.md)。

0.3.1 继续该工作流的性能路线：原生非 headless before、first after、final after 已捕获并保存原始逐帧数据，最终比较 matched。最终总览每次重绘 CPU p95 72.376→37.163 ms；正常地图 17.543→16.626 ms，但该组帧间隔 p95 略升，CANVAS calls 未下降，set_world 索引准备及可见行军／到达扫描更贵。第一轮的三个 CPU 尾部回退完整保留审计。基线用于指导稀疏特征、局部河流准备、纯坐标有界缓存与超长路线裁剪，未拆动态 Canvas 层。697 项本地检查由根代理确认，Windows CI 同样通过，实际原生与最终 Web 桌面/390 地图观察已通过；[0.3.1 发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.1) 与四项资产大小／digest 校验已完成，源码推送、标签与 [正式 Windows 包启动 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479418934) 均 success，正式 ZIP 下载并校验后实际运行导出客户端收到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`，故事 004 为 DONE。复现与限制见 [地图性能说明](MAP-PERFORMANCE.zh.md)、[报告](../production/polish/world-map-report-2026-10-06.md) 和 [验证记录](QA.zh.md)。四项预算未设定、默认 enforce warn，预算符合性仍为 NOT ASSESSED；GPU timing unavailable，开发机结果不代替 Windows/Web/手机性能。

0.2.0 的 227 项检查、浏览器经营链路及正式 Windows 包启动 CI 属于历史证据：[运行记录](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37467149603)。Windows 导出、headless 启动、人工桌面试玩和长期游戏体验分别记录；Windows 人工长局、真实 iPhone 多点触控、控制器与 Steam Deck 尚未验证。

## 桌面端后续顺序

1. **补平台采样与快照长局。** 原生同场比较及原始数据已保存；下一步在 Windows/Web 及目标设备取得单独数据，并测定期世界快照刷新和缓存清空的长局尾部。CPU 绘制与实际帧间隔分别报告，不能以导出成功或 CPU 微基准代替顺滑度验证；动态 Canvas 分层与地形图集待后续证据和架构决定。
2. **补充桌面长局与输入体验。** 当前键盘输入、窄屏入口和正式 Windows 包启动已验证，下一轮用 Windows 人工试玩记录长期焦点、存档与地图体验；手柄和 Steam Deck 单独规划与验证。
3. **再接 Steam。** 确定 Steam App ID、接入方式与账号后端后，设计少量可验证的成就和云存档策略。云存档需明确进度归属、版本冲突及跨端恢复；公网多人进度由账号与服务器权威结算管理。排行榜、创意工坊和在线状态按玩法需求逐步加入。

每项功能继续在独立 Godot 仓库开发，使用真实规则与存档验证。技能中的通用引擎比较不覆盖项目已选目标，也不代替当前平台文档或实际运行测试。
