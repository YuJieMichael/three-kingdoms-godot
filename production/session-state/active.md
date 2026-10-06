# 当前状态

<!-- STATUS -->
Godot＋GDScript 独立客户端 0.3.1 大地图测量与路线裁剪已完成实现、697 项本地检查、非 headless 原生 before/first/final 捕获与最终原生/Web 桌面/390 观察；故事 004 仍 IN PROGRESS，等待发布资产校验及正式 Windows 包启动 CI。最终总览 CPU draw p95 72.376→37.163 ms，正常地图 17.543→16.626 ms；正常帧间隔 p95 略升、draw calls 未下降、世界快照准备更贵，first 回退与额外成本完整保留。四项预算未设定、默认 enforce warn，GPU/Windows/Web 性能未测。最终 Windows/Web 导出已成功；原仓库干净 HEAD c7674df、vendor/bridge 无差异、原 Pages 未部署，Graphify 本地 573/1712/30，未启用 watcher/hook/上传。
<!-- /STATUS -->

<!-- CHECKPOINT -->
**Updated:** 2026-10-06
**Branch:** `main`
**Current task:** /dev-story + /perf-profile — production/epics/godot-client/story-004-map-performance.md（IN PROGRESS）
**Next step:** 提交已完成实现与报告，发布 0.3.1 并核对四项 GitHub asset digest；正式 Windows ZIP 下载、校验及启动 CI 通过后更新结案文档并 story-done。
**Blocked on:** 无；正常发布与 CI 验证尚在推进。
**Files in progress:** 实现与基准已冻结；故事 004、session 和发布文档等待 GitHub digest／Windows CI 的最终完成证据。
**Run result:** OBSERVED — before/first/final 均 valid，两份 comparison matched，五份 JSON 归档 production/polish/data。根代理最终独立确认 482＋215＝697 本地通过；源码 review 无阻塞，Godot 导入无 ERROR。原生拖动 32→40,36、41% 总览/H/KP_Add/任务侧栏、最终 Web 桌面与390拖动/缩放/回城已实际观察，warn/error=[]；截图 docs/screenshots/map-performance-*.jpg。Windows/Web 已导出且本地四项 SHA256 完整，GitHub digest／正式 Windows 包启动 CI 尚待完成。
**Open questions:** 无需更改引擎或规则；CPU 绘制／帧间隔／GPU／RSS 的测量边界和未设预算明确记录，动态 Canvas 分层保留后续范围。
<!-- /CHECKPOINT -->

本机独立预览 http://127.0.0.1:17339/ 使用 .local/play 新城进度，不覆盖它进行测试；测试使用独立目录，性能基准只实例化地图与合成 DTO，不连接规则服务或读写玩家数据。原仓库和原 Pages 保持不变，不部署公网多人／Supabase，不启用 watcher、hook、语义后端或图谱上传。根代理确认原仓库 clean／HEAD c7674df、vendor/bridge 无差异；Graphify 按原 flags 本地更新为 573 节点、1712 边、30 社区，仍不覆盖 .gd。

0.3.1 最终 Windows/Web 包已导出；发布链接、源码标签、GitHub 四项资产 digest 与正式包启动 CI 在完成后补入，不能以历史运行代替。动态分层、图集、正式美术、完整名将／招降、联盟、计谋及各州扩容留待后续；账号权威服务与 Steamworks 尚未配置。

历史 0.3.0：[发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.0)、[正式 Windows 包 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37472454474)，全绿，GODOT_SMOKE_OK canonical_revision=0 tiles=4096。历史 0.2.0：[发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.2.0)、[Windows 正式包 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37467149603)。Windows 人工长局、真实手机多点触控、控制器、Steam Deck 与 Steamworks 尚未验证。
