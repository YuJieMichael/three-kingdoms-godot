# 当前状态

<!-- STATUS -->
故事 005 声音、菜单与剧情工具已实现，固定提交引入 Sound Manager、Dialogue Manager 及 Maaack 独立分页组件；菜单复用原设置，新增音量和经营/出征引导。40 项新检查及 675 项原 Godot 检查通过，Windows CI 22 项规则＋715 项 Godot 共 737 项全绿。Windows/Web 导出、PCK smoke 和实际 Web 桌面/390 验证通过，非 headless 原生截图确认布局。草稿 PR #1 待审阅合并，未发布。导出 EXE 启动被自动审批策略拦截，真实手机音频解锁、听感与长局未验证。战斗、规则、地图数据与存档格式未修改。
<!-- /STATUS -->

<!-- CHECKPOINT -->
**Updated:** 2026-10-06
**Branch:** `feat/presentation-tools`
**Current task:** production/epics/godot-client/story-005-presentation-tools.md（IMPLEMENTED / 草稿 PR #1 待审阅）
**Next step:** 审阅 https://github.com/YuJieMichael/three-kingdoms-godot/pull/1；正式配乐、人工听感和长局另行验证。
**Blocked on:** 无。
**Files in progress:** 无；实现、基准、报告及结案文档已冻结。
**Run result:** Windows CI 37488545553 在 1dbce92 success，737 项检查全绿；当前实现与证据见 docs/PRESENTATION-TOOLS.zh.md。此前故事 004 的地图测量与发布记录见其独立故事和报告。
**Open questions:** 无需更改引擎或规则；CPU 绘制／帧间隔／GPU／RSS 的测量边界和未设预算明确记录，动态 Canvas 分层保留后续范围。
<!-- /CHECKPOINT -->

本机独立预览 http://127.0.0.1:17339/ 使用 .local/play 新城进度，不覆盖它进行测试；测试使用独立目录，性能基准只实例化地图与合成 DTO，不连接规则服务或读写玩家数据。原仓库和原 Pages 保持不变，不部署公网多人／Supabase，不启用 watcher、hook、语义后端或图谱上传。根代理确认原仓库 clean／HEAD c7674df、vendor/bridge 无差异；Graphify 按原 flags 本地更新为 573 节点、1712 边、30 社区，仍不覆盖 .gd。

0.3.1 [最终 Windows/Web 包已发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.1)，标签源码 `ce131a8b62941cc537d2bc7398f247ad9b796d17`，GitHub 四项资产大小／digest 均与本地一致。[源码推送 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479201825)、[标签 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479270820) 与 [正式 Windows 包启动 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479418934) 均 success，head 均为上述标签源码，Windows 同样通过 697 项检查。正式 ZIP 下载并核对 SHA256 后执行导出客户端 headless smoke，收到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`，日志 `.local/windows031-ci.log`。动态分层、图集、正式美术、完整名将／招降、联盟、计谋及各州扩容留待后续；账号权威服务与 Steamworks 尚未配置。

历史 0.3.0：[发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.0)、[正式 Windows 包 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37472454474)，全绿，GODOT_SMOKE_OK canonical_revision=0 tiles=4096。历史 0.2.0：[发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.2.0)、[Windows 正式包 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37467149603)。Windows 人工长局、真实手机多点触控、控制器、Steam Deck 与 Steamworks 尚未验证。
