# 当前状态

<!-- STATUS -->
用户要求继续运行，故事006已Complete：0.5.0本机1–8人房间、邀请码加入与自己的城池恢复。原城池/兵种/自动结算规则保留，策略重做继续暂缓。

1187项核心本地检查通过，365项独立包审计通过；真实Web/macOS房间创建/加入/满员恢复、原生20骑驻扎召回与重启恢复600可用骑兵、最终GodotWeb390大厅和粮草12000战报交付已观察。Windows/Web最终包已重导出，无凭据或私人进度混入。原私人原生客户端已恢复；0.5.0未公开发布，Windows EXE/CI未执行，公网及Steamworks未配置。
<!-- /STATUS -->

<!-- CHECKPOINT -->
**Updated:** 2026-10-06
**Branch:** `main`
**Current task:** /story-done — production/epics/godot-client/story-006-room-lobby.md（Complete）。
**Next step:** 本机房间试玩可运行。正式跨电脑服务需独立游戏后台配置与用户部署偏好；尚未自动开始新故事。
**Blocked on:** 无本轮阻塞；正式后台配置不在已完成的本机房间范围。
**Files in progress:** 无在编写源码；0.4.0/0.5.0全部为独立仓库本地未提交变更，未推送/发布。
**Run result:** OBSERVED / PASS — 1187项核心检查、365项独立包审计及真实原生/Web；production/polish/room-lobby-report-2026-10-06.md 与 docs/screenshots/rooms-lobby-final-050.png。
**Open questions:** 等待用户对正式后台的选择。当前Supabase只有其他业务项目，未写入/新建；正式外网账号/百人压力/Steamworks另行配置。策略重做暂缓。
<!-- /CHECKPOINT -->

新增房间大厅 http://127.0.0.1:17343/lobby 使用 .local/room-play-050，保持运行并保留空白大厅入口；不再展示测试会话秘密。原生房间测试窗口已结束，私人客户端启动成功恢复青溪城。

本机独立私人预览 http://127.0.0.1:17339/ 使用 .local/play 新城进度，不覆盖它进行测试；原生私人客户端已恢复并继续使用原userdata。共享演练 http://127.0.0.1:17342/ 使用 .local/pvp-play-040，私有邀请页为该目录join-world.html；Web演练页继续可用，刷新需重新从邀请页加入。测试使用独立目录，性能基准只实例化地图与合成DTO。原仓库和原Pages保持不变，不部署公网多人／Supabase，不启用watcher、hook、语义后端或图谱上传。根代理确认原仓库clean／HEAD c7674df、旧vendor/bridge无差异；Graphify按原flags本地更新为726节点、2218边、40社区，仍不覆盖.gd。

0.3.1 [最终 Windows/Web 包已发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.1)，标签源码 `ce131a8b62941cc537d2bc7398f247ad9b796d17`，GitHub 四项资产大小／digest 均与本地一致。[源码推送 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479201825)、[标签 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479270820) 与 [正式 Windows 包启动 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479418934) 均 success，head 均为上述标签源码，Windows 同样通过 697 项检查。正式 ZIP 下载并核对 SHA256 后执行导出客户端 headless smoke，收到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`，日志 `.local/windows031-ci.log`。动态分层、图集、正式美术、完整名将／招降、完整联盟界面、计谋及各州扩容留待后续；当前先完成共享攻防闭环；账号权威服务与 Steamworks 尚未配置。

历史 0.3.0：[发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.0)、[正式 Windows 包 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37472454474)，全绿，GODOT_SMOKE_OK canonical_revision=0 tiles=4096。历史 0.2.0：[发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.2.0)、[Windows 正式包 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37467149603)。Windows 人工长局、真实手机多点触控、控制器、Steam Deck 与 Steamworks 尚未验证。
