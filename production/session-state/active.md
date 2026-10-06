# 当前状态

<!-- STATUS -->
Godot＋GDScript 新客户端 0.3.0 已实现可配置电脑输入与地图导航，故事 003 为 IN PROGRESS。范围为 InputMap 动作、1–5 页面切换、H 回城/T 事务/O 存档/K 按键设置、重绑冲突反馈与本机持久化，以及弹窗和文字编辑隔离。根代理确认原有 227 项和新增输入 255 项共 482 项通过；macOS 原生冲突、重绑后重启生效、恢复默认及地图操作，最终 Web 桌面文字/焦点隔离、地图操作和 390 窄屏设置均已实际观察，浏览器 warn/error 日志为空。最终 Windows/Web 导出成功；正式发布与 Windows 发布包启动 CI 待完成。独立私有仓库为 YuJieMichael/three-kingdoms-godot；原仓库和规则快照 c7674df 保持不变。引擎 Godot 4.7.2 stable 标准版。
<!-- /STATUS -->

<!-- CHECKPOINT -->
**Updated:** 2026-10-06
**Branch:** `main`
**Current task:** /dev-story — production/epics/godot-client/story-003-pc-input.md（可配置电脑输入与地图导航，IN PROGRESS）
**Next step:** 提交独立仓库并发布 0.3.0，校验正式 Windows ZIP 的启动 CI；证据齐全后关闭故事。
**Blocked on:** 无。
**Files in progress:** 实现、检查、原生/Web 观察及最终导出已完成并冻结；当前仅正式发布、Windows 包 CI 和证据关闭，不修改源码或重写玩家进度。
**Run result:** OBSERVED / PARTIAL — 482 项检查通过、Godot 解析无 ERROR；macOS 原生冲突/F9 重绑/重启/恢复默认、Right 地图移动、小键盘加号缩放和 H 回城已观察。最终 Web 存档 TextEdit 输入 12345k 保持编辑，Esc 后立即 2 切舆图；H/Equal/D 地图操作、390×844 事务入口/设置滚动/恢复默认已验证，warn/error 日志为空。截图 docs/screenshots/pc-input-*.jpg。0.3.0 最终 Windows/Web 导出成功，正式发布与 Windows 正式包 CI 为 PENDING。
**Open questions:** 无；沿用 c7674df 权威规则、原存档和本地桥接范围。
<!-- /CHECKPOINT -->

本机独立预览 http://127.0.0.1:17339/ 使用 .local/play 新城进度，不覆盖它进行测试；测试进度须使用独立目录，不与玩家原网页存档混用。没有修改原 Pages，没有部署公网多人或正式 Supabase。本轮之后再评估性能基线、其余管理界面、正式美术和扩州规划，账号权威后端与 Steamworks 为后续配置。

上轮历史证据：[v0.2.0 发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.2.0)；[Windows 正式包运行 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37467149603)。Windows 人工长局、真实 iPhone 多点触控、控制器、Steam Deck 与 Steamworks 尚未验证。
