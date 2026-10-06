# 当前状态

<!-- STATUS -->
新版游戏名已统一为「山河策」，当前为0.6.0-dev.1账号联机开发预览，故事007仍为In Progress。Web/Godot账号入口、本人房间恢复、Supabase Auth适配、私有Postgres持久化及HTTPS部署基础已实现；原城池/兵种/自动结算规则和私人/四账号/0.5本机房间入口保留，策略重做继续暂缓。

账号与PG测试使用本机真实PostgreSQL17.10和测试Supabase REST。最终1400项本地自动检查通过（Node97、SceneTree1284、HTML脚本fixture19），独立最终包另1742项审计、服务器包128项审计通过，包括跨标签Cookie切换后的X-Expected-Account核对、账号绑定、真实SQL单实例/失败停止和离线战斗返程只结算一次；实际浏览器登录、席位恢复和390账号大厅已观察。正式Supabase游戏项目、费用和公网Node主机仍待用户选择，尚未开通或部署；不能把本地测试当作公网/跨电脑验证。

0.5房间故事006继续Complete：历史1187项核心本地检查、365项独立包审计及真实Web/macOS观察保留。0.5源码与表现工具已经合并，并以e5f5c6c推送独立仓库；0.5发布包未公开发布，历史Windows运行边界不变。

0.5历史观察：真实Web/macOS房间创建/加入/满员恢复、原生20骑驻扎召回与重启恢复600可用骑兵、最终GodotWeb390大厅和粮草12000战报交付已观察。Windows/Web最终包已重导出，无凭据或私人进度混入；原私人原生客户端已恢复。0.5 Windows EXE/CI尚未执行，公网及Steamworks未配置。报告与截图继续见production/polish/room-lobby-report-2026-10-06.md、docs/screenshots/rooms-lobby-final-050.png。
<!-- /STATUS -->

<!-- CHECKPOINT -->
**Updated:** 2026-10-06
**Branch:** `main`
**Current task:** production/epics/godot-client/story-007-online-foundation.md（In Progress），版本0.6.0-dev.1。
**Next step:** 新组织「山河策工作室」已创建；为连接器授权此组织后查询项目费用、创建独立游戏项目，配置HTTPS主机并进行跨电脑验收。
**Blocked on:** 现有连接器没有新组织权限；正式项目费用与公网Node托管目标仍待落实。本地客户端及服务器包已保存，尚未部署公网。
**Files in progress:** 本次提交保存0.6账号、PG、客户端、部署配置及最终验证说明；不是正式云端上线。0.5与表现工具合并检查点e5f5c6c已推送。
**Run result:** PASS — 1400项本地自动检查、独立最终包1742项审计与服务器包128项审计；源码4936de9的Windows/PostgreSQL CI completed/success（37518089341），后续仅补验收文档；最终实际Web及390账号大厅已观察。证据见production/polish/online-foundation-report-2026-10-06.md。历史0.5报告仍见production/polish/room-lobby-report-2026-10-06.md。
**Open questions:** 新组织的连接器授权、项目费用、公网Node主机与域名。现有连接项目属于其他业务，未用于游戏；百人压力、正式Steamworks与策略重做仍在后续范围。
<!-- /CHECKPOINT -->

0.5会话保留记录：房间大厅 http://127.0.0.1:17343/lobby 使用 .local/room-play-050，保留空白大厅入口；不展示测试会话秘密。原生房间测试窗口已结束，私人客户端启动成功恢复青溪城。以下本机进度路径不用于0.6临时Auth/PG测试。

本机独立私人预览 http://127.0.0.1:17339/ 使用 .local/play 新城进度，不覆盖它进行测试；原生私人客户端已恢复并继续使用原userdata。共享演练 http://127.0.0.1:17342/ 使用 .local/pvp-play-040，私有邀请页为该目录join-world.html；Web演练页继续可用，刷新需重新从邀请页加入。测试使用独立目录，性能基准只实例化地图与合成DTO。原仓库和原Pages保持不变；已创建独立Supabase组织，但没有开通游戏项目或部署公网，不启用watcher、hook、语义后端或图谱上传。历史根代理确认原仓库clean／HEAD c7674df、旧vendor/bridge无差异；0.5 Graphify按原flags本地更新为726节点、2218边、40社区，仍不覆盖.gd；0.6本地最终刷新1102节点、2957边、58社区，SQL与.gd覆盖限制仍在。

2026-10-06 组织操作：用户拒绝修改原房产业务组织，改为创建新组织，并选定「山河策工作室」。组织ID为 `mwctnnafccwgcezatckw`，Free方案，网页确认0 projects；名称已保存，截图 `.local/supabase-shanhece-organization.png`。MCP get_organization对此ID返回权限不足，因此网页登录与现有连接器访问范围尚未接通，不能借用其他业务项目。

2026-10-06 名称更新：新版Godot工程的窗口、顶栏、菜单、房间/账号大厅与后续打包说明改为「山河策」。Godot `application/config/name` 继续作为原桌面和Web `user://` 的兼容标识；仓库路径、EXE/PCK入口、JSON存档和服务协议名保留。独立 `build/brand-preview` 已导出并通过真实浏览器观察：标签/顶栏/菜单为新名，城池界面和官府1级正常，canonical资源随时间推进，无console error/warn；截图 `.local/shanhece-game-preview.png`。3个GDScript解析及Node/Python语法通过，隔离原生启动确认旧userdata目录和新窗口/菜单标题，canonical smoke返回 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`。此名称验证使用独立临时进度；既有私人进度和改名前归档包未覆盖，也未重新发布历史版本。品牌diff经独立只读复核，避免了Web平台name覆盖导致的存档目录变化；Graphify按原flags刷新仍为1102节点、2957边、58社区。

0.3.1 [最终 Windows/Web 包已发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.1)，标签源码 `ce131a8b62941cc537d2bc7398f247ad9b796d17`，GitHub 四项资产大小／digest 均与本地一致。[源码推送 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479201825)、[标签 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479270820) 与 [正式 Windows 包启动 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479418934) 均 success，head 均为上述标签源码，Windows 同样通过 697 项检查。正式 ZIP 下载并核对 SHA256 后执行导出客户端 headless smoke，收到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`，日志 `.local/windows031-ci.log`。动态分层、图集、正式美术、完整名将／招降、完整联盟界面、计谋及各州扩容留待后续；当前先完成共享攻防闭环；账号权威服务与 Steamworks 尚未配置。

历史 0.3.0：[发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.0)、[正式 Windows 包 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37472454474)，全绿，GODOT_SMOKE_OK canonical_revision=0 tiles=4096。历史 0.2.0：[发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.2.0)、[Windows 正式包 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37467149603)。Windows 人工长局、真实手机多点触控、控制器、Steam Deck 与 Steamworks 尚未验证。
