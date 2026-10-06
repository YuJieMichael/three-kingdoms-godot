# 当前状态

2026-10-06。用户优先完成游戏本体，Claude斜杠命令配置和真实Supabase联调暂缓。

<!-- STATUS -->
独立新版「山河策」当前为 **0.6.0-dev.2 本机玩法收尾**，故事008 Complete。任务/每日/史诗/官爵/俸禄、野将画像与招降、培养装备、伤兵俘虏/城防/黄巾来袭、多城/建城/运输、城外样板/领地采集、自动建设研究、宝物/商城入口完成。既有canonical规则和进度格式保留；技能及策略重做继续暂缓。

1814项本地自动检查通过：Node131、SceneTree1664、HTML脚本fixture19；最终包另192项检查通过。实际Web全部23个分区、桌面与390关键管理界面、礼包入库和任务推进已观察；最终编译PCK两包都读取实际状态与4096地图。Windows EXE本版本尚未执行，公网/Steam/真实手机/自然长局未验证。详见 `production/polish/playable-completion-report-2026-10-06.md`。

新存档使用正常奖励和道具完成30弓首战；测试跳到队列结束时间且没用加速，累计800分钟未加速模拟时间不等于实际玩家耗时。后期用明确的合法高阶库存验证3次攻县城、第二章6关和第三章首节点开放，不冒充自然成长平衡。

故事007仍 In Progress，按用户要求暂缓联调。独立Free组织「山河策工作室」和项目「山河策」已完成数据库/Auth基础配置；3个人工创建、已确认账号和私密启动配置保留。已有数据库密码尚未被实际读到；本轮不启动17345、不询问或重设凭据，不创建密码助手，不改其他业务项目。恢复联网工作后再验真实Auth/PG及公网托管，先不付费。
<!-- /STATUS -->

<!-- CHECKPOINT -->
**Updated:** 2026-10-06
**Branch:** `main`
**Current task:** production/epics/godot-client/story-008-playable-completion.md — Complete，0.6.0-dev.2。
**Next step:** 用户从17347试玩新版，重点反馈引导、加速道具使用和中后期资源节奏。后续若继续开发，先评估真实等待与长期成长，再扩展内容；技能/计谋和联网需遵守用户后续方向。
**Blocked on:** 当前本机玩法收尾没有阻断。真实云联调仍等待用户恢复该范围；不以此阻止本机开发。
**Files in progress:** 无剩余生产实现；源码、故事及QA报告保存本轮结果。本地包位于build/playable-0602，未公开Release。
**Run result:** OBSERVED — 实际最终Web桌面及390宽度，production/qa/evidence/story-008/30–39；PASS — 1814项自动检查、192项最终包检查、实际原生/编译PCK状态与地图smoke。并未对玩家原生窗口操作。
**Open questions:** 实际新手等待和长局平衡、Windows人工试玩、正式美术、各州扩容、联网与Steamworks。当前故事只完成本机规则入口/闭环，不能叫完整商业版。
<!-- /CHECKPOINT -->

## 当前可继续试玩

- 新版本独立预览 `http://127.0.0.1:17347/`，数据 `.local/playable-0602-preview`，最终Web导出 `build/playable-0602/web`。真实UI领取官府1礼包及首个任务后停在安置百姓；这是独立测试新城，可继续玩。后台保留运行。
- 原私人试玩17339使用 `.local/play`，不用于测试；原生私人客户端的userdata和窗口未改动。
- 原共享四账号17342使用 `.local/pvp-play-040`，邀请页与角色密钥不输出到Git或答复。
- 原0.5房间17343使用 `.local/room-play-050`；恢复密钥须用户自行保存。
- 17345真实Supabase服务及17346密码助手均未启动。暂时原生QA进程已退出，不占用玩家原生窗口。

## 构建、保存与图谱

Windows/Web两包为0.6.0-dev.2，SHA256和字节数见QA报告与build-manifest.json。包内为完整资源、官方Node及规则服务；真实账号配置与存档不入包。Godot application/config/name继续「三国城志 · Godot」以保持user://兼容，实际窗口、页面及界面显示「山河策」。

原three-kingdoms仍clean，HEAD c7674df45b9595405e57907524e737e633b0ff63，Pages不部署；vendor/legacy及vendor/shared无差异。Graphify按既有code-only/exclude标记本地更新1169节点、3097边、62社区；.gd和SQL提取限制保留，不启用watcher、hook、语义后端或图谱上传。

## 历史验收

0.6账号基础报告 `production/polish/online-foundation-report-2026-10-06.md` 记录历史1400项本地检查及源码4936de9的Windows/Linux CI，不能等同真实Supabase或本轮Windows EXE运行。

0.5房间报告 `production/polish/room-lobby-report-2026-10-06.md` 记录1187项核心检查、365项独立包审计，以及实际Web/macOS房间与返程入库。0.5源码及表现工具以e5f5c6c推送；0.5包未公开Release。

公开版本仍为0.3.1（ce131a8b62941cc537d2bc7398f247ad9b796d17），正式发布包Windows启动CI37479418934成功，源码及标签CI亦成功。历史697项证据和地图性能见docs/QA.zh.md、production/polish/world-map-report-2026-10-06.md；不把历史CI当作本轮导出执行证明。
