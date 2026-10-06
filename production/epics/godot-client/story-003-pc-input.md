# 可配置电脑输入与地图导航

Status: DONE
Last Updated: 2026-10-06
Story Type: UI / Integration / Config
GDD: design/game-brief.md
ADR Governing Implementation: N/A — 沿用 Godot＋GDScript 原生界面及权威规则桥接；为客户端动作建立 InputMap，不更换引擎、规则快照或存档格式。
Dependencies: production/epics/godot-client/story-002-city-management.md — DONE

## 目标

让电脑玩家使用键盘移动地图、切换常用页面和打开事务，同时可查看并调整按键。采用 pc-games 的动作抽象原则，键盘操作与现有鼠标、触屏界面共存。游戏内按钮仍可到达相同功能，原网页版与原 GitHub Pages 保持不变。

## 验收

- [x] 为地图移动与缩放建立 InputMap 动作；地图能通过键盘连续移动，并遵守既有边界、缩放和回城逻辑。
- [x] 默认 1–5 切换五个主页面，H 回城、T 事务、O 存档、K 按键设置；按钮和键盘进入相同界面，不复制规则结算。
- [x] 按键设置展示动作与当前绑定，允许重新绑定及恢复默认；重复、保留或不支持的按键有明确反馈，不悄悄覆盖其他动作。
- [x] 有效绑定保存在本机客户端设置中，重新启动或网页重新加载后恢复；与游戏存档分离，不覆盖玩家进度。
- [x] 文本输入、SpinBox 数量编辑、弹窗和按键捕获期间，地图移动与页面快捷键不会误触发；Tab、Enter、Esc 保留原生焦点、确认与关闭操作。
- [x] 桌面和 390 像素窄屏可打开、滚动并操作按键设置；长动作名、反馈文字和按钮不被截断，触屏仍可使用原按钮。
- [x] 原有 227 项检查继续通过，新增 `tests/input_test.gd` 检查覆盖绑定校验、冲突与持久化、导航和输入隔离；CI 执行新检查。
- [x] 实际观察 macOS 桌面窗口与 Web：地图移动、快捷键、编辑隔离、重绑冲突与重新加载，并保存截图及观察记录。
- [x] 生成 Windows 与 Web 0.3.0 试玩包；正式 Windows ZIP 校验后实际启动 CI 通过，分别记录导出与发布包运行结果。
- [x] 只提交和发布独立新仓库；原仓库、原网页、规则快照及玩家存档不变，未开启 watcher、hook 或图谱上传。

## 实现范围

将动作映射、按键配置持久化和设置弹窗与客户端页面及地图衔接。按键只是触发现有显示或规则命令的入口，继续等待权威回执。游戏规则与资源收益不在客户端重写。CCGS 沿用 minimal 的 dev-story → story-done，只有实际验收证据完成后才关闭故事。

## 不包含

本轮不接 Steamworks、云存档、公开多人、手柄或 Steam Deck；不宣称性能或 FPS 改善，不替代性能测量；不迁移剩余管理界面、扩州地图、完整名将技能或改动 vendor/legacy。

## 验证记录

原有真实 HTTP 桥接 22 项、地图 24 项、城池/战斗 31 项、客户端 71 项、经营界面 79 项重新执行通过；新增 `tests/input_test.gd` 255 项通过，共 482 项。检查直接注入生产客户端的真实输入事件，覆盖绑定冲突、保留按键、持久化、失败回滚、损坏配置、同帧短按、按钮焦点、方向键与 WASD、反向键抵消、缩放边界、文字与弹窗隔离、窗口失焦和窄屏布局。Godot 源码解析无 ERROR，CI 配置已纳入新检查。

macOS 原生窗口实际使用 K 打开设置：城池绑定 2 时明确拒绝冲突，重绑 F9 后保存，正常关闭并重启后 F9 成功切换城池；通过界面恢复默认 1 后切换仍成功。地图方向键在 GUI 焦点前处理后，Right 短按使镜头 32→34，小键盘加号使缩放 80→90，H 返回主城。截图为 `docs/screenshots/pc-input-conflict-native.jpg`、`pc-input-settings-native.jpg`、`pc-input-map-native.jpg`。此轮只读页面和客户端设置，没有执行经济命令或用测试进度覆盖玩家存档。

最终 Web 实际存档 TextEdit 输入 `12345k` 时未触发游戏快捷键，Esc 关闭后立即按 2 成功切换舆图，无需额外点击；新增检查亦覆盖弹窗关闭后的焦点恢复。H 回城、`=` 缩放 80→90%、D 六次镜头 32→38 均可见。390×844 窄屏通过事务菜单进入 350 像素宽设置弹窗，滚动可见 15 项与恢复默认/关闭按钮，并实际恢复默认；浏览器 warn/error 日志为空。截图为 `pc-input-text-web.jpg`、`pc-input-focus-web.jpg`、`pc-input-map-web.jpg`、`pc-input-settings-390-web.jpg`、`pc-input-settings-bottom-390-web.jpg`。最终原生默认设置截图为 `pc-input-settings-native-final.jpg`。

Windows/Web 0.3.0 最终导出成功并已发布为 [v0.3.0](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.0)，标签/源码为 `3a48bf5df20a708199f3c69a1a0409c8cadac92a`，四项发布资产 digest 与本地一致，SHA256 清单见 `docs/QA.zh.md`。[正式 Windows CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37472454474) 全绿：官方 Godot 安装、导入、全部 GDScript 检查与源码 smoke 成功，日志确认 `INPUT_TEST_CHECKS=255 failures=0`。下载正式发布 ZIP、核对 SHA256、解压后执行 `ThreeKingdoms.exe --headless -- --smoke`，收到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`。原仓库工作区干净，HEAD 与远端仍为 c7674df；0.2.0 的运行结果仅作为历史证据保留。

## Completion Notes

Completed: 2026-10-06
Criteria: 10 / 10 passing，无延期验收。
Deviations: 无；未进行 Windows 人工长局、真实 iPhone 多点触控或性能 FPS 基线测量；手柄、Steam Deck、Steamworks 与公开多人为故事外范围。
Test Evidence: 482 项本地与 Windows CI 检查、macOS 原生与实际 Web 桌面/390 窄屏截图、正式 Windows ZIP 校验后的导出包启动，见上文与 `docs/QA.zh.md`。
Run result: OBSERVED — `docs/screenshots/pc-input-*.jpg` 保留按键设置、冲突、地图、存档编辑与弹窗返回、窄屏入口和滚动的真实截图；正式 Windows 包 headless 返回 GODOT_SMOKE_OK。
Code Review: 独立代码复核通过，无阻塞缺陷；CCGS minimal 未执行完整部门审批或质量覆盖门禁。
