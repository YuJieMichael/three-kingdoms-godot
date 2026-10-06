# 当前状态

<!-- STATUS -->
Godot＋GDScript 新客户端 0.2.0 已实现市场交易、城守/税率与客栈招募。227 项本地检查通过，实际电脑/390 窄屏浏览器经营操作与重新加载已观察，Windows/Web 试玩包已导出。当前等待发布后的 Windows 导出包实际启动 CI，故事保持 IN PROGRESS。独立私有仓库为 YuJieMichael/three-kingdoms-godot；原网页 GitHub 保持 c7674df、工作区干净。引擎 Godot 4.7.2 stable 标准版。上一版 0.1.1 的 Windows 运行结果为历史证据，详见 docs/QA.zh.md。
<!-- /STATUS -->

<!-- CHECKPOINT -->
**Updated:** 2026-10-06
**Branch:** `main`
**Current task:** /dev-story — production/epics/godot-client/story-002-city-management.md（原生城池经营与将领招募，IN PROGRESS）
**Next step:** 提交独立新仓库源码、发布 v0.2.0 预览包并执行 Windows 发布包启动 CI；收到实际运行结果后更新验证记录并关闭故事。
**Blocked on:** 无；仅剩发布与 Windows 导出包启动验证。
**Files in progress:** 0.2.0 源码与测试、README、docs/QA.zh.md、截图、本故事与发布说明，待最终提交及 CI 结果。
**Run result:** OBSERVED — IAB 网页 1280×720 与 390×844 下市场、城守/税率、客栈、事务菜单、将领表及重新加载；macOS 原生城池与三类经营面板只读打开观察，未更改桌面存档。证据 docs/screenshots/management-*.jpg，原生截图 management-city-native.jpg。Windows 导出包运行待 CI。
**Open questions:** 无；沿用 c7674df 权威规则、原存档和本地桥接范围。
<!-- /CHECKPOINT -->

本机独立预览 http://127.0.0.1:17339/ 使用 .local/play 新城进度，不覆盖它进行测试；测试进度须使用独立目录，不与玩家原网页存档混用。没有修改原 Pages，没有部署公网多人或正式 Supabase。本轮之后再继续其余管理界面、正式美术和扩州规划，账号权威后端与 Steamworks 为后续配置。
