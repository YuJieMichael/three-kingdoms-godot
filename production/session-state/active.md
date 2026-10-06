# 当前状态

<!-- STATUS -->
Godot＋GDScript 独立客户端 0.3.1 大地图测量与路线裁剪已完成实现、697 项本地与 Windows CI 检查、非 headless 原生 before/first/final 捕获与最终原生/Web 桌面/390 观察；故事 004 为 DONE，发布、四项资产大小／digest 校验及三项 CI 全部完成，正式 Windows ZIP 校验后实际启动通过。最终总览 CPU draw p95 72.376→37.163 ms，正常地图 17.543→16.626 ms；正常帧间隔 p95 略升、draw calls 未下降、世界快照准备更贵，first 回退与额外成本完整保留。四项预算未设定、默认 enforce warn，GPU/Windows/Web 性能未测。最终 Windows/Web 导出已成功；原仓库干净 HEAD c7674df、vendor/bridge 无差异、原 Pages 未部署，Graphify 本地 573/1712/30，未启用 watcher/hook/上传。
<!-- /STATUS -->

<!-- CHECKPOINT -->
**Updated:** 2026-10-06
**Branch:** `main`
**Current task:** /story-done — production/epics/godot-client/story-004-map-performance.md（DONE，八项验收全部完成）
**Next step:** 本轮待办为 0；后续平台性能采样、持续长局或其余界面迁移另行选择。
**Blocked on:** 无。
**Files in progress:** 无；实现、基准、报告及结案文档已冻结。
**Run result:** COMPLETE — before/first/final 均 valid，两份 comparison matched，五份 JSON 归档 production/polish/data。根代理最终独立确认 482＋215＝697 本地通过；源码 review 无阻塞，Godot 导入无 ERROR。原生拖动 32→40,36、41% 总览/H/KP_Add/任务侧栏、最终 Web 桌面与390拖动/缩放/回城已实际观察，warn/error=[]；截图 docs/screenshots/map-performance-*.jpg。Windows/Web 已发布，GitHub 四项资产大小／digest 与本地一致，源码推送、标签与正式 Windows 包启动 CI 均 success；正式 ZIP 下载并校验后实际启动收到 GODOT_SMOKE_OK canonical_revision=0 tiles=4096。
**Open questions:** 无需更改引擎或规则；CPU 绘制／帧间隔／GPU／RSS 的测量边界和未设预算明确记录，动态 Canvas 分层保留后续范围。
<!-- /CHECKPOINT -->

本机独立预览 http://127.0.0.1:17339/ 使用 .local/play 新城进度，不覆盖它进行测试；测试使用独立目录，性能基准只实例化地图与合成 DTO，不连接规则服务或读写玩家数据。原仓库和原 Pages 保持不变，不部署公网多人／Supabase，不启用 watcher、hook、语义后端或图谱上传。根代理确认原仓库 clean／HEAD c7674df、vendor/bridge 无差异；Graphify 按原 flags 本地更新为 573 节点、1712 边、30 社区，仍不覆盖 .gd。

0.3.1 [最终 Windows/Web 包已发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.1)，标签源码 `ce131a8b62941cc537d2bc7398f247ad9b796d17`，GitHub 四项资产大小／digest 均与本地一致。[源码推送 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479201825)、[标签 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479270820) 与 [正式 Windows 包启动 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479418934) 均 success，head 均为上述标签源码，Windows 同样通过 697 项检查。正式 ZIP 下载并核对 SHA256 后执行导出客户端 headless smoke，收到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`，日志 `.local/windows031-ci.log`。动态分层、图集、正式美术、完整名将／招降、联盟、计谋及各州扩容留待后续；账号权威服务与 Steamworks 尚未配置。

历史 0.3.0：[发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.0)、[正式 Windows 包 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37472454474)，全绿，GODOT_SMOKE_OK canonical_revision=0 tiles=4096。历史 0.2.0：[发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.2.0)、[Windows 正式包 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37467149603)。Windows 人工长局、真实手机多点触控、控制器、Steam Deck 与 Steamworks 尚未验证。
