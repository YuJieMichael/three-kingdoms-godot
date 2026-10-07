# 当前状态

2026-10-07。用户要求城池与城外的历史感来自空间结构，继续优先游戏本体；Claude斜杠命令配置和真实Supabase联调暂缓。

<!-- STATUS -->
2026-10-07：当前源版本0.6.0-dev.12，story018围墙城防完成。1级木栅栏，2级起石墙逐级升高；四周与南门点击原城防建造/升级面板，城务有替代入口。沿用真实site占位和canonical规则，城防营署是原地块外观。只用已完成等级，不提前显示排队结果。

六组GD3157项、native868项、Node77项通过，Web导出通过。本机17359沿用原存档，服务改用build/wall-0612/web，私有本地备份在.local/wall-preview。story009–017历史验证见各story报告；本次没有重新发布Windows安装包或实测Windows EXE、实体手机。

用户明确要求全部开发更新上传GitHub；范围为独立three-kingdoms-godot仓库，原three-kingdoms/Pages不动。本机存档、缓存、环境配置、构建产物和Graphify图不入库。Graphify已按原code-only排除参数刷新；.gd及IIFE覆盖限制不变。
<!-- /STATUS -->

<!-- CHECKPOINT -->
**Updated:** 2026-10-07
**Branch:** main；本次同步story009–018及其素材、文档与验证。
**Current task:** production/epics/godot-client/story-018-perimeter-defenses.md — Complete，0.6.0-dev.12。
**Next step:** 17359试玩新的城景与建设决策；当前六项范围完成。
**Blocked on:** 本轮无阻断；真实云联调仍暂缓。
**Files in progress:** story017代码/资产/测试/报告/证据与build/city-polish-0611-final已收尾。
**Run result:** PASS — GD5973、native1361、Node38、package205、PCK93×2、HTTP20；OBSERVED — 最终Web1280/390、0warning/error、0消费命令/revision0/持久化save unchanged。
**Open questions:** Windows硬件/实体手机、动态居民、全国州郡规则、正式公网/Steam；prepared截图不是自然长局。
<!-- /CHECKPOINT -->

## 当前可继续试玩

- 最新六项更新`http://127.0.0.1:17359/`，exec55026/tab81、viewport恢复；来源17358保存只复制save.json，完整Windows/Web包在build/city-polish-0611-final。本轮全部验收通过，原进度与副本摘要不变。
- 下文旧地址和tab记录为历史；旧服务仍留存，本任务创建的旧测试标签已关闭。

- 内城36格新版`http://127.0.0.1:17358/`，数据`.local/city-grid-0610-preview`仅复制17357 save.json，Web`build/city-grid-0610-final/web`；最终1280/390实际观察、revision0/无mutation/source与copy存档不变，exec31250/tab78保留，viewport已恢复。

- 大地图新版`http://127.0.0.1:17357/`，数据`.local/map-art-0609-preview`仅复制17356 save.json，Web`build/map-art-0609/web`；最终1280/390实际观察、revision0/无mutation/source与copy存档不变，exec78920/tab77保留，viewport已恢复。

- 建筑贴图新版`http://127.0.0.1:17356/`，数据`.local/commanding-art-0608-preview`为17355副本，Web`build/commanding-art-0608-final/web`；实际最终1280/390已观察，revision0无消费、save不变；exec82143/tab76保留，viewport恢复。

- 历史结构新版`http://127.0.0.1:17355/`，数据`.local/historic-0607-preview`为17351进度副本，Web`build/historic-0607/web`；实际最终1280/390已观察，revision0无消费；exec77975与tab73保留，viewport已恢复，旧预览保留。
- 战争界面新版`http://127.0.0.1:17351/`，数据`.local/war-ui-0606-preview`，Web`build/war-ui-0606/web`；revision0，无消费/派兵指令。服务exec41307保留，交付tab71，临时viewport已重置。
- 侦察新版`http://127.0.0.1:17350/`，数据`.local/scouting-0605-preview`，Web`build/scouting-0605/web`；revision0，无消费/派兵指令。服务exec90965保留，交付tab69。
- 成长与收支新版`http://127.0.0.1:17349/`，数据`.local/growth-0604-preview`，Web为`build/growth-0604/web`；新城仍在奉诏立城，revision0，没有消费或派兵指令。服务exec33747保留运行，预览tab67为本轮交付。
- 界面旧版17348数据`.local/ui-polish-0603-preview`、Web`build/ui-polish-0603/web`，服务4942保留，新城在奉诏立城。
- 本机完整玩法旧版17347数据`.local/playable-0602-preview`、Web`build/playable-0602/web`，服务60634保留，停在安置百姓。
- 原私人试玩17339用`.local/play`；原生私人客户端userdata和窗口未改动。
- 原共享四账号17342用`.local/pvp-play-040`；0.5房间17343用`.local/room-play-050`，不输出角色/恢复密钥。
- 17345真实Supabase及17346密码助手均未启动；本轮隔离QA Godot已退出。

## 构建、保存与图谱

0.6.0-dev.10最终包build/city-grid-0610-final；原始生成prompt、7建筑PNG+地面与17区域源摘要、最终包SHA、QA/浏览器/存档核对见production/qa/evidence/story-016及production/polish/city-grid-art-report-2026-10-07.md。Graph最终本地同flags刷新1327节点/3508边/77社区。其后dev.9等计数与结果为历史记录。

0.6.0-dev.9最终包build/map-art-0609；资产prompt、当前source/包SHA、QA/浏览器/存档核对见production/qa/evidence/story-015及production/polish/world-map-art-report-2026-10-07.md。Graph最终本地同flags刷新1327节点/3508边/77社区。其后dev.8图谱计数为历史记录。

0.6.0-dev.8最终包在`build/commanding-art-0608-final/`；SHA256/字节数、资产摘要、QA和包检查见production/qa/evidence/story-014，报告production/polish/commanding-city-art-report-2026-10-07.md。内置image_gen生成，两图源像素不改；最终图谱1320节点/3496边/78社区，no external backend/watchers/hooks/upload。

0.6.0-dev.7最终包在`build/historic-0607/`，最终SHA256、字节数与验收聚合见production/qa/evidence/story-013/build-manifest.json、qa-summary.json和package-audit-summary.json；报告production/polish/historic-city-report-2026-10-07.md。历史0.6.0-dev.6包仍在`build/war-ui-0606/`，旧SHA256与字节数仅对应战争界面报告和story-012证据。包内完整资源、官方Windows Node与规则服务，真实账号配置与存档不入包。application/config/name继续「三国城志 · Godot」以保持user://兼容；实际窗口/页面/界面为「山河策」。

原three-kingdoms仍clean，HEAD`c7674df45b9595405e57907524e737e633b0ff63`，Pages不部署；vendor/legacy与vendor/shared无差异。Graphify最终本地code-only/exclude刷新与无标签聚类完成，1320节点、3496边、78社区；.gd和SQL提取限制保留，不启用watcher/hook/外部语义后端或上传。010新增bridge存档可选计数兼容旧存档，严格验证限制，跨日/跨城/重启/并发回执已测。

## 历史验收

0.6账号基础报告 `production/polish/online-foundation-report-2026-10-06.md` 记录历史1400项本地检查及源码4936de9的Windows/Linux CI，不能等同真实Supabase或本轮Windows EXE运行。

0.5房间报告 `production/polish/room-lobby-report-2026-10-06.md` 记录1187项核心检查、365项独立包审计，以及实际Web/macOS房间与返程入库。0.5源码及表现工具以e5f5c6c推送；0.5包未公开Release。

公开版本仍为0.3.1（ce131a8b62941cc537d2bc7398f247ad9b796d17），正式发布包Windows启动CI37479418934成功，源码及标签CI亦成功。历史697项证据和地图性能见docs/QA.zh.md、production/polish/world-map-report-2026-10-06.md；不把历史CI当作本轮导出执行证明。
