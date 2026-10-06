# 当前状态

<!-- STATUS -->
Godot＋GDScript 新客户端 0.3.0 已完成并发布可配置电脑输入与地图导航，故事 003 为 DONE。范围为 InputMap 动作、1–5 页面切换、H 回城/T 事务/O 存档/K 按键设置、重绑冲突反馈与本机持久化，以及弹窗和文字编辑隔离。482 项本地及 Windows CI 检查通过；macOS 原生输入与最终 Web 桌面/390 窄屏均已实际观察，浏览器 warn/error 日志为空。最终 Windows/Web 包已发布，标签/源码为 3a48bf5df20a708199f3c69a1a0409c8cadac92a，四项资产 digest 与本地一致。CI 37472454474 全绿，正式 Windows ZIP 校验后的客户端启动返回 GODOT_SMOKE_OK canonical_revision=0 tiles=4096。独立私有仓库为 YuJieMichael/three-kingdoms-godot；原仓库工作区干净，HEAD/远端与规则快照 c7674df 保持不变。引擎 Godot 4.7.2 stable 标准版。
<!-- /STATUS -->

<!-- CHECKPOINT -->
**Updated:** 2026-10-06
**Branch:** `main`
**Current task:** /story-done — production/epics/godot-client/story-003-pc-input.md（可配置电脑输入与地图导航，COMPLETE / DONE）
**Next step:** 本轮输入故事已完成，试玩 v0.3.0 并记录体验问题；下一轮按 PC 工作流为性能基线、桌面长局或其余管理迁移建立新故事。
**Blocked on:** 无。
**Files in progress:** 无；实现、验证、发布与结案记录均已完成。
**Run result:** OBSERVED — 482 项本地与 Windows CI 检查通过、Godot 解析无 ERROR；macOS 原生冲突/F9 重绑/重启/恢复默认、Right 地图移动、小键盘加号缩放和 H 回城已观察。最终 Web 存档 TextEdit 输入 12345k 保持编辑，Esc 后立即 2 切舆图；H/Equal/D 地图操作、390×844 事务入口/设置滚动/恢复默认已验证，warn/error 日志为空。截图 docs/screenshots/pc-input-*.jpg。0.3.0 最终 Windows/Web 已发布，四项资产 digest 核对一致；正式 Windows 包 CI 37472454474 全绿，GODOT_SMOKE_OK canonical_revision=0 tiles=4096。
**Open questions:** 无；沿用 c7674df 权威规则、原存档和本地桥接范围。
<!-- /CHECKPOINT -->

本机独立预览 http://127.0.0.1:17339/ 使用 .local/play 新城进度，不覆盖它进行测试；测试进度须使用独立目录，不与玩家原网页存档混用。没有修改原 Pages，没有部署公网多人或正式 Supabase。本轮之后再评估性能基线、其余管理界面、正式美术和扩州规划，账号权威后端与 Steamworks 为后续配置。

[v0.3.0 发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.0)；[本轮正式 Windows 包 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37472454474)，全绿。临时 17341 QA 服务已关闭；用户 17339 与原生客户端仍运行。

上轮历史证据：[v0.2.0 发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.2.0)；[Windows 正式包运行 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37467149603)。Windows 人工长局、真实 iPhone 多点触控、控制器、Steam Deck 与 Steamworks 尚未验证。
