# 大地图性能测量与路线裁剪

Status: DONE
Last Updated: 2026-10-06
Story Type: Logic / Integration / Visual
GDD: design/game-brief.md
ADR Governing Implementation: N/A — 沿用现有 Godot 地图和 canonical 规则；本轮仅测量客户端绘制、裁剪可视路线并减少无效重绘，不改变世界坐标、经济、行军结算或存档格式。
Dependencies: production/epics/godot-client/story-003-pc-input.md — DONE

## 目标

为后续扩州地图建立可重复的本机渲染基线，修复长路线穿屏却缺失的虚线，并按测量结果减少地图上的无效工作。原游戏世界继续为 64×64；256×256 场景只是隔离的客户端压力样本。

## 验收

- [x] 独立原生非 headless 基准以固定视口、场景、种子与摄像机路径采集优化前后数据；记录 Godot、设备、渲染器、样本数及测量限制，不读写玩家存档。
- [x] 记录地图 CPU 绘制时间、帧间隔、重绘次数、引擎绘制调用和可用内存监视值；CPU 绘制时间与完整 FPS、GPU 时间明确区分，缺少数据或预算的项标为 NOT ASSESSED。
- [x] 超过旧 9000 像素上限的行军路线仍可显示穿过视口的部分，两端屏外的穿屏路线不会被误删，虚线相位随摄像机移动保持一致。
- [x] 视口外的虚线计算随可见线段长度增长，而非沿整条长路线迭代；驻扎、采集、返回和到达时间沿用既有语义。
- [x] 若测量支持减少无效行军重绘，视口中可见部队仍持续移动并在抵达后更新；过滤器、拖动、缩放、键盘和任务据点保持原行为。
- [x] 原 482 项检查通过，新增几何与真实绘制回归检查通过并进入 Windows CI；实际原生及最终 Web 观察保留截图。
- [x] 独立 Godot 仓库生成并发布 0.3.1 Windows/Web 包，核对资产摘要；正式 Windows ZIP 下载、校验及实际启动验证通过。
- [x] 性能报告、原始测量、复现命令及剩余问题保存到仓库；原仓库和原 Pages 保持不变，无 watcher、hook 或图谱上传。

## 边界

采用 pc-games 的先测量再优化与 CCGS minimal dev-story → story-done。`performance.enforce` 为默认 warn；项目没有已提交的帧率、帧预算、绘制调用或内存预算，不据模板数字宣称达标。只对有证据的小范围绘制开销进行优化。动态层拆分、地形图集、正式美术和坐标规则扩容如需要架构变更，留待后续设计。

本轮不接 Steamworks、云存档、公共账号或百人联网，也不调整技能或经济。合成 200 条行军路线不代表 200 名真实在线玩家；开发机结果不代表 Windows、真实手机或 Steam Deck 的性能。

## 验证记录

非 headless before、第一轮 after 与最终 after 已归档至 `production/polish/data/`，三次捕获均 valid，两份 comparison 均 matched。相同 Apple M1 / macOS 27.0.1 / Godot 4.7.2 debug / OpenGL compatibility，1280×800、VSync、限帧 60；各组 30 热身／150 采样帧，seed 439903。基准 SHA256 为 `0222249719b1845686dc012adbbb1b62aa9f054f6110593ea04e60fd7542d461`，最终地图源码 SHA256 为 `4d0fbb443343438e77d6a9b9194a019dec0562fb0c88b0d0673cf0c21cc90179`。报告与复现均已完成，不混用 CPU draw、帧间隔、GPU 或 RSS。

最终总览每次重绘 CPU p95 72.376→37.163 ms，64_pan 17.543→16.626 ms；200 pan 每采样帧 CPU p95 43.986→39.144 ms，仍为两次重绘。64_pan 帧间隔 p95 67.432→67.678 ms 略升，CANVAS calls 未下降，单次 set_world 各场景更贵、到达／可见性扫描增加 process CPU。第一轮三个 CPU 尾部回退及后续优化另行记录。完整原始数据和限制见 `production/polish/world-map-report-2026-10-06.md`、`docs/MAP-PERFORMANCE.zh.md`；四项预算未设定仍为 NOT ASSESSED，GPU 与目标平台性能未采。

根代理最终独立运行确认原有 482 项＋新增 `tests/map_render_test.gd` 215 项，共 697 项本地通过；`.local/map-031-final-render.log` 为 `MAP_RENDER_TEST_CHECKS=215 failures=0`，无 ERROR。新增涵盖双精度长线、相位、可见候选数量、SceneTree 动画、筛选、到达边沿、稀疏索引更新及几何缓存容量、坐标与缩放等价。独立源码复核确认完成刷新、双精度比例、有界纯几何缓存与颜色／阈值，未发现阻塞问题。

最终原生实际观察拖动镜头 32,32→40,36、缩小至 41% 显示中原分区、H 回城及 KP_Add 恢复 80%、河畔荒田侧栏 29,35 与配兵出征按钮；保留玩家 userdata，只查看未出征。最终 Web 在独立 17341 QA 服务完成桌面拖动／远近缩放／回城及同任务侧栏，390×844 完成拖动、缩放和回城；warn/error 日志为空，截图为 `docs/screenshots/map-performance-*.jpg`。临时 QA tab 已关闭、viewport reset；用户 17339 最终资产已重新加载、原 `.local/play` 保留，原生客户端继续运行。

Windows/Web 0.3.1 最终导出已发布至 [v0.3.1](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.1)，标签源码 `ce131a8b62941cc537d2bc7398f247ad9b796d17`；四项 GitHub 资产大小／digest 均与本地一致，详见 `docs/QA.zh.md` 与 `.local/release031-verified.json`。[源码推送 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479201825)、[标签 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479270820) 与 [正式 Windows ZIP 下载／校验／实际启动 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479418934) 均 success，head 均为上述标签源码。Windows 日志确认 697 项通过，包括 `MAP_RENDER_TEST_CHECKS=215 failures=0`；源码 smoke 和正式导出包均收到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`。正式 ZIP 下载并核对 SHA256 后直接执行 `ThreeKingdoms.exe --headless -- --smoke`，不是以旧 0.3.0 证据替代，亦不代替 Windows 人工长局或性能验证。

根代理最终核对原仓库 clean／HEAD c7674df、vendor/bridge 无差异，原 Pages 未部署。Graphify 同原 code-only 排除 flags 及 cluster-only/no-label 本地刷新为 573 节点、1712 边、30 社区；.gd 仍未覆盖，未启用外部语义后端、watcher、hook 或上传。八项验收全部完成，当前待办为 0；故事 004 按 story-done 结案。
