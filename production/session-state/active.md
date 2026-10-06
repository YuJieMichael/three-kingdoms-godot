# 当前状态

<!-- STATUS -->
Godot＋GDScript 新客户端 0.2.0 已实现并发布市场交易、城守/税率与客栈招募，故事 002 为 DONE。227 项本地检查通过，实际电脑/390 窄屏浏览器经营操作与重新加载、macOS 原生面板已观察；Windows/Web 试玩包已发布，正式 Windows ZIP 校验后的 headless 启动 CI 全绿，输出 GODOT_SMOKE_OK。发布/标签源码为 aa963a8d7584103595983896d8681d2b59e8bfc1。独立私有仓库为 YuJieMichael/three-kingdoms-godot；原网页 GitHub 保持 c7674df、工作区干净。引擎 Godot 4.7.2 stable 标准版。运行与截图证据详见 docs/QA.zh.md。
<!-- /STATUS -->

<!-- CHECKPOINT -->
**Updated:** 2026-10-06
**Branch:** `main`
**Current task:** /story-done — production/epics/godot-client/story-002-city-management.md（原生城池经营与将领招募，COMPLETE / DONE）
**Next step:** 本轮两个故事均完成；试玩 v0.2.0 并记录体验问题。下一轮按 PC 工作流为可配置输入、性能基线或其余管理迁移建立新故事。
**Blocked on:** 无。
**Files in progress:** 无；功能、验证与发布记录已完成。
**Run result:** OBSERVED — IAB 网页 1280×720 与 390×844 下市场、城守/税率、客栈、事务菜单、将领表及重新加载；macOS 原生城池与三类经营面板只读打开观察，未更改桌面存档。证据 docs/screenshots/management-*.jpg，原生截图 management-city-native.jpg。Windows 正式导出包 headless 启动通过：actions/runs/37467149603，GODOT_SMOKE_OK canonical_revision=0 tiles=4096。
**Open questions:** 无；沿用 c7674df 权威规则、原存档和本地桥接范围。
<!-- /CHECKPOINT -->

本机独立预览 http://127.0.0.1:17339/ 使用 .local/play 新城进度，不覆盖它进行测试；测试进度须使用独立目录，不与玩家原网页存档混用。没有修改原 Pages，没有部署公网多人或正式 Supabase。本轮之后再继续其余管理界面、正式美术和扩州规划，账号权威后端与 Steamworks 为后续配置。

[v0.2.0 发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.2.0)；[Windows 正式包运行 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37467149603)。Windows 人工长局、真实 iPhone 多点触控、控制器、Steam Deck 与 Steamworks 尚未验证。
