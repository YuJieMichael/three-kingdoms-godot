# 声音、菜单与剧情工具

这次集成只扩展表现层。`vendor/legacy`、`bridge`、存档格式与现有经济、行军和战斗结算保持不变。新代码不计算伤害、不发奖励、不重新创建武将数据库。

## 实际接入

- Sound Manager 2.6.2：完整插件位于 `addons/sound_manager`，作为 autoload 注册。`src/presentation_audio.gd` 提供 Music、Sounds、UI 三条独立总线，首次主动点击后才启动音乐。界面按钮播放提示音；游戏音效由 `command_completed` 触发，失败请求不播放成功音效。菜单支持独立音量、静音和试听，设置单独保存在 `user://presentation-audio.cfg`，保存失败保留原值。
- Maaack Game Template：选择性导入独立的 `paginated_tab_container.gd`，用于“游戏 / 声音 / 鸣谢”分页和 PageUp/PageDown 切换。没有接入模板的存档、改键、音乐控制器或场景切换框架。项目专用菜单为 `src/presentation_menu.gd`，复用原有按键、存档、连接设置，并增加新手引导入口。
- Dialogue Manager 4.1.0：完整插件位于 `addons/dialogue_manager`，包含 Godot 编辑器中的剧情编辑工具。`data/dialogue/intro.dialogue` 是可编辑的新手引导，包含经营、出征、自行探索三条分支；`src/presentation_dialogue.gd` 使用真实 DialogueResource 遍历和原生窗口展示。

上游固定提交与 MIT 许可证见 `THIRD_PARTY_NOTICES.md` 和 `docs/licenses/`。`scripts/build.py` 将三份新许可证一起复制进 Windows/Web 分发包的 licenses 目录。

## 使用

启动后显示菜单，点“返回游戏”继续；游戏顶部“菜单”随时打开。连接入口移入菜单，原顶部“事务”和“存档”保留。窄屏可从菜单进入按键设置。弹窗期间沿用现有游戏快捷键隔离，Tab/Enter/Esc 使用 Godot 原生焦点、确认和关闭行为。菜单不暂停规则服务；界面已明确提示建设和行军继续按实际时间推进。

音效与背景音乐当前是代码合成的原创示范素材，方便即时试听，不代表正式三国配乐。正式素材可替换 `_streams` 中的 AudioStream；声音播放继续交给 Sound Manager。

在 Godot 编辑器打开 intro.dialogue 可编辑引导。当前剧情只有展示和选项，没有 `do`、奖励、资源写入或存档字段。未来剧情需要奖励、招募等行为时，应由客户端适配代码调用现有 `KingdomApi.command`，收到规则回执后再推进相关表现；不能用剧情变量替代权威进度。

## 验证

运行：

```text
godot --headless --path . --editor --import
godot --headless --path . --script tests/presentation_test.gd
godot --path . --script tests/presentation_test.gd -- --capture
```

新测试使用独立临时用户目录，不读取或覆盖现有玩家进度。40 项检查涵盖真实声音池、首次交互启动、音量持久化、静音、写入失败回滚、真实剧情分支、菜单入口、插件分页、快捷键隔离、关闭恢复和 1280/390 宽度适配。捕获模式保存 `.local/presentation-*.png` 并运行实际非 headless Windows 渲染。

原有 675 项 Godot 检查通过；完整客户端连接独立本地预览服务得到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`。Node 规则测试本机 21/22 通过，余下符号链接隔离用例因本机权限在创建测试链接时返回 EPERM，未进入断言；不是本次规则修改引起。该权限受阻用例不改写或绕过，继续保留在原 CI 中。

Windows 与 Web release 导出成功，导出日志没有 SCRIPT ERROR/ERROR。官方 Godot 引擎加载导出的 Windows PCK 连接独立预览服务，得到同样的 GODOT_SMOKE_OK。启动导出的 Windows EXE 被本机自动审批策略阻止，仅返回“blocked by policy”，因此不声称验证了该 EXE 的实际启动。

实际 Web 浏览器验证了桌面菜单、出征剧情分支、返回菜单、声音页、音乐静音保存、390×844 布局及刷新后保留静音。浏览器 warn/error 日志为空；截图见 `docs/screenshots/presentation-web-*.jpg`。Windows 非 headless 原生测试运行 40 项通过，截图确认桌面与 390 窄屏菜单、音量与剧情布局，没有运行时错误。Godot 运行环境与导出模板取自官方 4.7.2-stable 发布，并按官方 SHA512 清单校验。

本轮未合并 main、未打发布标签，也未替换原网页。实际听感、长局以及真实手机音频解锁仍需人工体验。
