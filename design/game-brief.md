# Godot 迁移试玩 · 0.3.1 大地图测量与裁剪

2026-10-06。用户选择 Godot＋GDScript，目标 Steam 与网页；原网页项目及已发布页面保持不变，另建独立仓库。

0.1.1 已完成原生大地图、城池与战斗视图、建设/训练/任务/出征主要操作、本地存档兼容、Windows 与网页导出，以及相同规则 API 验证。0.2.0 已发布市场交易、城守与税率管理、客栈招募，使建设、补给和出征形成经营循环。0.3.0 已完成动作抽象的电脑输入、键盘地图导航与可保存的重绑设置；482 项本地与 Windows CI 检查、原生桌面重绑/重启恢复/地图操作及实际 Web 桌面/390 窄屏输入已通过，最终 Windows/Web 包已发布并核对四项资产 digest，正式 Windows 发布包启动 CI 全绿。故事 003 为 DONE，见 `production/epics/godot-client/story-003-pc-input.md` 和 `docs/QA.zh.md`。Steamworks 接入在客户端验证之后。

0.3.1 已完成，故事 004 为 DONE。非 headless before、first after、final after 已同条件捕获与归档；最终四个动态场景每次重绘 CPU 均值/p95 降低，总览 p95 72.376→37.163 ms，但正常地图帧间隔 p95 略升、draw calls 没有下降、世界快照准备成本增加。修复超长虚线丢失并保留原相位，减少屏外／筛选隐藏行军重绘，短行程在卡顿后仍刷新抵达。overview 使用稀疏索引，森林与山峰纯坐标几何缓存各有 2048 上限，河流保留原采样格并缩小准备范围。根代理最终确认原 482＋新增地图 215，共 697 项本地与 Windows CI 通过；实际原生与最终 Web 桌面/390 地图观察已完成。最终导出已发布至 [v0.3.1](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.1)，源码标签 `ce131a8b62941cc537d2bc7398f247ad9b796d17`，四项资产大小／digest 校验通过，源码推送、标签与 [正式 Windows 包启动 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479418934) 均 success；正式 ZIP 下载校验后实际启动收到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`，八项验收全部完成。

0.3.0 的五页面、事务、存档、设置、地图平移/缩放/回城及独立按键配置继续保留；文字编辑、弹窗和窗口失焦隔离不变。后续继续其余管理和完整名将/招降、联盟与计谋，再规划正式美术与各州扩容；本轮不调整英雄技能或经济平衡，不拆动态 Canvas 层。

性能数据分开报告 CPU draw、分层、帧间隔和引擎内存，GPU timing 为 UNAVAILABLE；项目未设四项预算，默认 enforce warn，不能据模板数字宣称达标。合成 256×256／200 行军是客户端压力样本，不是已扩州、200 玩家服务器或目标平台性能承诺。报告与复现保存在 `production/polish/`、`docs/MAP-PERFORMANCE.zh.md`。

风格：写实古代战争，以暗炭、铜金、青灰城墙与连续地形为主；画面用可扩展原生绘制，避免原网页格子列表。地图支持跟手拖动、锚点缩放、军队路线/到达时间、远近层级；规则世界维持 64×64，后续各州扩容需要独立规则与存档迁移。

桌面打包本地 Node 规则服务与完整资源，GDScript 负责客户端，JavaScript 规则快照负责原作结算。网页通过相同 API 连接服务；正式共享多人仍需要带账号与服务端权威存档的部署，不将本地桥接直接暴露公网。
