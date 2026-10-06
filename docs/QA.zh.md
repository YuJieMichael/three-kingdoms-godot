# Godot 验证记录

## 0.5.0 1–8人房间与席位恢复

2026-10-06。**1187项核心本地检查通过**（HTTP66＋SceneTree1121），另有**365项独立包审计通过**。实际Web创建/加入/满员恢复，macOS原生加入/20骑驻扎召回/重启恢复600可用轻骑，以及最终GodotWeb390大厅和同一战报粮草12000交付均已观察。

损坏JSON被覆盖的P1已修复，6种无效值均保留原字节；明确409拒绝后派遣等待文案残留的P2已修复，运输未确认仍禁止重复派遣。Windows/Web已最终导出，代码/启动入口/清单检查通过，最终PCK在macOS验证。**0.5.0为本地包，Windows EXE尚未在Windows运行，公网/Supabase/Steamworks未部署。** 大厅未确认登记只保留在当前窗口内存，请保持窗口并重试原请求；正式跨电脑后台仍待配置。

完整数据、最终包哈希和边界见 [房间报告](../production/polish/room-lobby-report-2026-10-06.md)，入口见 [房间说明](ROOMS.zh.md)。

![最终房间大厅](screenshots/rooms-lobby-final-050.png)

## 0.4.0 四账号共享攻防

2026-10-06。**1040项本地检查通过**：HTTP45、原生客户端/地图/战斗/事务/输入840、共享API89、共享UI49、实际Web回执存储17。修复同账号多窗口操作覆盖、身份切换残留、旧回执回退、进程旧锁恢复竞态与跨账号实体ID碰撞，独立复核通过。

真实macOS/Web已观察援军驻扎、自动战斗、双方一致战报、返程交付及召回。最后修复后重新加载最终Web导出，原持久进度与已交付战报正确；最新原生20长枪兵援军驻扎、召回和自动返城已观察。Godot Windows/Web最终导出、包内模块与清单审计、独立包内Node攻防烟测均通过。当前为本地包，**0.4.0未公开发布，Windows exe/CI尚未运行**；不能套用下面0.3.1的成功记录。完整证据、最终包摘要与边界见 [共享PvP报告](../production/polish/shared-pvp-report-2026-10-06.md)。

![0.4.0 最终 Web 战报与资源交付](screenshots/pvp-web-final-040.png)

## 0.3.1 大地图测量与路线裁剪

2026-10-06，Godot `4.7.2.stable.official.ed1daf0bf`，标准版 GDScript。697 项本地与 Windows CI 检查、原生性能比较、最终原生／Web 观察、发布资产校验与正式 Windows 包运行验证均已完成，故事 004 为 DONE。本节记录0.3.1历史版本；以下 0.3.0、0.2.0 与更早结果均为历史证据。

### 实现与自动检查

长虚线按整条线与扩展视窗的交集生成可见 dash，从原起点计算相位，取消旧 600 段／约 9000 屏幕像素上限；内部双精度比例避免两百万像素线的端点误差。两端屏外仍可穿屏显示。行军每 50 ms 检查可见动态标记，屏外／筛选隐藏部队避免无用刷新；未来到达引用支持短行程或卡顿越过移动区间后的单次最终刷新，驻扎、采集和返回语义不变。

低于 46% 的远景使用原 y/x 顺序的城池／任务／主城稀疏索引，46% 及以上保持逐格细节；地形／森林／山峰颜色保持原值。纯坐标几何缓存每类上限 2048，缩放采用当前 pixels；河流保留原采样格、邻点、宽度与支流 `W/(3H)` 间距。山峰乘法顺序调整仅有极小浮点舍入差异，没有意图形状变化。

| 范围 | 通过数量 | 本轮证据 |
|---|---:|---|
| 桥接、地图、城池/战斗、客户端、事务与输入 | 482 | 根代理最终重新执行确认 |
| 新增几何、真实绘制、到达边沿与缓存 | 215 | 根代理独立复跑 `MAP_RENDER_TEST_CHECKS=215 failures=0`，无 ERROR |
| 合计 | 697 | 本地与 Windows CI 全部通过；源码推送、标签与正式包验证三项 CI 均 success |

新增检查使用隔离 DTO 与实际 SceneTree draw，覆盖长线几何、相位、可见候选量、连续动画、筛选、驻扎／采集、现有标签 margin、首次扫描前抵达、卡顿跨过到达、单次完成刷新、稀疏索引阈值／顺序／替换和缓存有界／坐标／缩放等价。根代理日志为 `.local/map-031-final-render.log`。独立源码复核无阻塞发现；源码导入无 ERROR。它们不连接规则服务或读写玩家存档，数学与 headless 回归不能代替性能捕获。

### 原生性能证据

三个原生非 headless 捕获均 valid，两份 comparison 均 matched，原始逐帧数据归档在 `production/polish/data/`。相同 Apple M1、macOS 27.0.1、Godot 4.7.2 debug、OpenGL compatibility、1280×800、VSync、限帧 60；各组热身 30／采样 150 帧。最终地图 SHA256 为 `4d0fbb443343438e77d6a9b9194a019dec0562fb0c88b0d0673cf0c21cc90179`，基准三次相同。完整数值与复现见 [报告](../production/polish/world-map-report-2026-10-06.md) 和 [说明](MAP-PERFORMANCE.zh.md)。

最终每次重绘 CPU p95：64_pan 17.543→16.626 ms、总览 72.376→37.163 ms、200 pan 22.133→19.645 ms、200 idle 23.175→18.710 ms。200 pan 每采样帧仍是两次重绘，其 CPU p95 为 43.986→39.144 ms。64_pan 帧间隔 p95 67.432→67.678 ms 略升，CANVAS calls 完全相同；单次 set_world 更贵，行军 process CPU 与引擎内存略增。第一轮三个 CPU 尾部回退的数据独立保留，随后代码优化得到 final 捕获，没有拼各轮最佳数据。

CPU draw 是插桩命令准备，分层时间属于其总量；帧间隔包含 VSync、渲染和调度，不是 GPU、完整 FPS 或输入延迟。引擎 static memory 不等于 RSS；GPU timing UNAVAILABLE。四项预算未设定、默认 enforce warn，符合性为 NOT ASSESSED — NO BUDGET。合成 256²／200 行军不是已扩州或 200 在线玩家，开发机捕获不是 Windows/Web 性能验证。

### 最终实际原生与 Web 观察

根代理在最终源码的 macOS 原生窗口保留原 userdata，拖动镜头 (32,32)→(40,36)，minus 缩到 41% 显示中原分区，H 回到 32，KP_Add 恢复 80%；选中河畔荒田后侧栏坐标 29,35、配兵出征按钮可见。此处只查看，未下达出征或经济命令。截图为 `map-performance-overview-native.jpg`、`map-performance-near-native.jpg`。

最终 `build/web` 在独立 17341 QA 服务完成 1280×800 桌面拖动、71% 近景、41% 总览、H 与 KP_Add 恢复 80%、同任务侧栏；截图为 `map-performance-near-web.jpg`、`map-performance-overview-web.jpg`。390×844 完成拖动、minus、H，镜头回到 32、缩放 71%，截图为 `map-performance-390-web.jpg`。浏览器 warn/error 日志为空。临时 QA tab 已关闭，viewport 已 reset；用户 17339 重新载入最终资产，原 `.local/play` 保留，原生客户端继续运行。未使用旧版截图代替本轮观察，窄屏不等于真实手机触控测试。

![0.3.1 最终原生总览](screenshots/map-performance-overview-native.jpg)

![0.3.1 最终原生近景与任务侧栏](screenshots/map-performance-near-native.jpg)

![0.3.1 最终网页总览](screenshots/map-performance-overview-web.jpg)

![0.3.1 最终网页近景与任务侧栏](screenshots/map-performance-near-web.jpg)

![0.3.1 最终网页窄屏地图](screenshots/map-performance-390-web.jpg)

### 发布资产与 Windows 实际启动

Windows/Web 最终导出成功并发布至 [v0.3.1](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.1)，标签源码为 `ce131a8b62941cc537d2bc7398f247ad9b796d17`。根代理通过 GitHub API 核对下表四项资产的字节数及 digest 均与本地一致，记录为 `.local/release031-verified.json`。

| 文件 | 字节数 | 本地与 GitHub 一致的 SHA256 |
|---|---:|---|
| ThreeKingdoms-Godot-v0.3.1-Windows-x64.zip | 86869201 | `84d15f246bb440e2fb895960adc198464c293cf8aefea4fe62b827f3be7913c6` |
| ThreeKingdoms-Godot-v0.3.1-Web-preview.zip | 59029064 | `78659bb2f6c634124afc214333aec5b7a6422e95a7c3fec79e8ecef587fb3e91` |
| build-manifest.json | 629 | `ac796ae78746148f0357889dffe011d326146bbd6ab4fa3c721ad8c6df26c19a` |
| SHA256SUMS.txt | 218 | `0f005505c0974d5a1022edc747fe915ba76e8c5f90cb4701e52e689219a04736` |

[源码推送 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479201825)、[标签 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479270820) 与 [正式 Windows 包下载／校验／启动验证](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479418934) 均 success，head 均为 `ce131a8b62941cc537d2bc7398f247ad9b796d17`。正式包验证日志 `.local/windows031-ci.log` 确认桥接 22、world 24、battle 31、client 71、management 79、input 255、map render 215，共 697 项通过，`MAP_RENDER_TEST_CHECKS=215 failures=0`。源码 smoke 与 `Verify exported Windows executable` 均收到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`。正式发布 ZIP 下载后通过 SHA256 校验，解压后实际执行 `ThreeKingdoms.exe --headless -- --smoke`，连接随包规则服务并载入权威状态与地图；这不代替 Windows 桌面人工长局或目标平台性能测量。

规则来源仍为 c7674df，runtime hash 为 `432f9fea6359c18a8d1e2655b09f97770718c3e676501c602c7897afd906a8b4`；vendor/legacy 与 bridge 无差异，原仓库工作区干净、HEAD 仍 c7674df，原 Pages 未部署。Graphify 按原 code-only 排除 flags 与 `cluster-only . --no-label` 刷新，为 573 节点、1712 边、30 社区；`.gd` 仍未覆盖，只有本地图谱更新，没有外部语义后端、watcher、hook 或上传。

动态 Canvas 分层、图集、正式美术、规则扩州和极长标签实际字体边界裁剪不在本轮，目前仍沿用左右 120、上下 35 px 标记 margin。缓存整体清空与定期快照的长局尾部、Windows 人工长局、真实手机、手柄、Steam Deck、Steamworks、公网多人及其压力表现未验证。

## 0.3.0 可配置电脑输入更新

2026-10-06，Godot `4.7.2.stable.official.ed1daf0bf`，标准版 GDScript。以下为根代理已执行与观察的本轮证据；0.2.0 与 0.1.1 记录保持为历史版本。0.3.0 实现、本地检查、macOS 原生操作、实际 Web 桌面/390 窄屏、最终 Windows/Web 导出与发布、正式 Windows 发布包启动 CI 均已完成，故事 003 为 DONE。

### 自动检查

| 范围 | 通过数量 | 本轮重点 |
| --- | ---: | --- |
| 真实 HTTP 桥接 | 22 | 重新验证原规则、事务费用、权威回执、持久化与隔离 |
| 原生地图 | 24 | 重新验证相机边界、拖动/缩放与行军语义 |
| 城池/战斗表现 | 31 | 重新验证建筑、军令与回合反馈 |
| 客户端 | 71 | 重新验证布局、状态保持、命令顺序与重连 |
| 原生城池事务 | 79 | 重新验证实际报价、回执刷新和桌面/窄屏管理表单 |
| 可配置输入 | 255 | 绑定校验、保存与失败回滚、损坏配置、真实事件导航、键盘地图和焦点隔离 |
| **总计** | **482** | 根代理独立运行确认全部通过 |

Godot 源码解析通过，未出现 ERROR。输入检查注入生产客户端的真实输入事件，并使用可丢弃的独立用户目录与 transport probe；未读写玩家进度。覆盖重复及原生 UI 保留键拒绝、带修饰组合、重新读取绑定、保存失败保留旧映射、损坏配置完整回退、原生 `ui_*` 不变、同帧按下/释放、WASD 与方向键、反向键抵消、地图边界和缩放锚点、按钮焦点、LineEdit/TextEdit/SpinBox、弹窗、失焦及 390 像素设置布局。导航和设置操作未发送经济或玩法命令。

CI 已执行 `tests/input_test.gd`，本轮 Windows 日志确认 `INPUT_TEST_CHECKS=255 failures=0`、`MANAGEMENT_TEST_CHECKS=79 failures=0`，其余原有检查亦通过。自动检查确认事件路由与布局边界，不代替实际桌面/网页观察。

### 实际 macOS 原生操作

在非 headless Godot 窗口中真实操作：

- 用 K 打开按键设置，将“查看城池”绑定为 2 时显示冲突并拒绝，原绑定保留。
- 改为 F9 后提示已保存；正常关闭客户端并重新启动，F9 成功切换城池，确认客户端绑定跨启动恢复。随后通过界面恢复默认 1，切换城池成功。
- 原方向键曾被 Godot GUI 焦点导航消费；调整为地图获得焦点时在 GUI 前路由后，Right 短按使镜头 32→34，小键盘加号使缩放 80→90，H 返回主城。其他控件仍保留原生焦点导航。

最终恢复默认后用 K 打开设置，截图为 `docs/screenshots/pc-input-settings-native-final.jpg`。此轮只读页面与本机按键设置，不执行经济命令，不导入测试进度覆盖玩家存档。其他截图为 `pc-input-conflict-native.jpg`、`pc-input-settings-native.jpg`、`pc-input-map-native.jpg`。

### 实际 Web 观察

最终导出版本使用临时 17341 端口进行独立 Web 输入验证：

- 存档 TextEdit 输入 `12345k` 时未触发页面或设置快捷键；Esc 关闭后立即按 2，无需额外点击就成功进入舆图。截图为 `docs/screenshots/pc-input-text-web.jpg` 和 `pc-input-focus-web.jpg`。修复弹窗关闭后的焦点恢复，避免已隐藏的存档编辑器继续拦截快捷键；新增检查覆盖同样的真实事件链路。
- H 回城，按 `=` 使缩放 80→90%，按 D 六次使镜头 32→38，地图位置变化可见；截图为 `pc-input-map-web.jpg`。
- 390×844 窄屏顶部隐藏按键按钮，仍可通过“事务→按键设置”进入。350 像素宽的弹窗完整容纳内容，滚动可查看 15 项及恢复默认/关闭按钮，并实际点击恢复默认；截图为 `pc-input-settings-390-web.jpg` 和 `pc-input-settings-bottom-390-web.jpg`。
- 最终浏览器 warn/error 日志为空。

窄屏使用实际浏览器视口尺寸验证，未进行真实手机多点触控。本轮未执行经济命令，也未用测试存档覆盖玩家进度。

### 导出产物

官方 Windows 与 Web 模板均导出成功，包内包含 Node Windows 24.21.0、规则服务、游戏资源与许可证。构建脚本仍在导入前生成 `build/.gdignore`。最终包清单：

| 文件 | 字节数 | SHA256 |
| --- | ---: | --- |
| ThreeKingdoms-Godot-v0.3.0-Windows-x64.zip | 86865047 | `8bf0128405e096e4dbf2f66ae0208d23e4fa7d0cc99681102e2f0fda98798c98` |
| ThreeKingdoms-Godot-v0.3.0-Web-preview.zip | 59024910 | `3546e8bdd267210a18d421ffd07e0e8762faafedc2e1565c56f7f3a553e41945` |

`build/build-manifest.json` 与 `SHA256SUMS.txt` 同时生成，规则来源仍为 `c7674df45b9595405e57907524e737e633b0ff63`，canonical runtime hash 保持 `432f9fea6359c18a8d1e2655b09f97770718c3e676501c602c7897afd906a8b4`。本轮只修改独立 Godot 仓库；不更改 vendor/legacy、原仓库或原 GitHub Pages，不启用 watcher、hook 或图谱上传。

### 发布与运行边界

[v0.3.0 预览发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.0) 已创建，标签与源码指向 `3a48bf5df20a708199f3c69a1a0409c8cadac92a`。两个 ZIP 的 GitHub digest 与上表一致；清单文件 `build-manifest.json` 的 SHA256 为 `0993f3a370c8c4877678a005ddf02483769d8880dcd04ac78d54767d29e244aa`，`SHA256SUMS.txt` 为 `64dc51d84f186fec83a5830bff1e269918dedefbc23aae3203a3520f606b499f`，四项发布资产 digest 均与本地核对一致。

[Windows CI 运行](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37472454474) 在同一源码提交全绿。官方 Godot 安装与校验、导入、全部原生 GDScript 检查、源码客户端 smoke 和 `Verify exported Windows executable` 均 success。正式发布 ZIP 下载并核对 SHA256，解压后直接执行 `ThreeKingdoms.exe --headless -- --smoke`，收到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`。这确认正式 Windows 导出包能启动、连接随包规则服务并载入权威状态与地图，不等于 Windows 桌面人工长局或 Steam 成品验证。

原仓库工作区、HEAD 与远端均经根代理确认保持 `c7674df45b9595405e57907524e737e633b0ff63`，未发布原 Pages。临时 17341 QA 服务已关闭，本机玩家 17339 与原生客户端继续运行。

本轮未测得性能 FPS 基线，未验证 Windows 人工长局、真实 iPhone 多点触控、手柄、Steam Deck、Steamworks、公网账号/共享世界或百人压力。按键设置的浏览器用户目录与原生用户目录分离，不提供跨设备云同步。

### 本地图谱与复核

独立代码复核通过，未发现阻塞缺陷。Graphify 沿用 `extract . --code-only --exclude '.claude/**' --exclude 'docs/engine-reference/**'` 和 `cluster-only . --no-label` 完成最终刷新，为 553 节点、1662 边、29 社区；没有外部语义后端、上传、watcher 或 hook。Graphify 0.9.76 不识别 `.gd`，IIFE 图谱覆盖仍不完整，Godot 输入实现以源码、真实 SceneTree 和运行证据为准。

![0.3.0 原生按键冲突反馈](screenshots/pc-input-conflict-native.jpg)

![0.3.0 原生按键设置](screenshots/pc-input-settings-native.jpg)

![0.3.0 最终原生默认按键设置](screenshots/pc-input-settings-native-final.jpg)

![0.3.0 原生地图键盘操作](screenshots/pc-input-map-native.jpg)

![0.3.0 网页存档文字输入隔离](screenshots/pc-input-text-web.jpg)

![0.3.0 关闭存档后键盘切换舆图](screenshots/pc-input-focus-web.jpg)

![0.3.0 网页地图键盘平移与缩放](screenshots/pc-input-map-web.jpg)

![0.3.0 390 像素窄屏按键设置](screenshots/pc-input-settings-390-web.jpg)

![0.3.0 窄屏设置滚动至恢复默认与关闭按钮](screenshots/pc-input-settings-bottom-390-web.jpg)

## 0.2.0 城池经营更新

2026-10-06，Godot `4.7.2.stable.official.ed1daf0bf`，标准版 GDScript。0.2.0 本地检查、实际网页经营验证与 macOS 原生面板观察已通过；Windows/Web 包已发布，正式 Windows 导出包 headless 启动 CI 通过。以下 0.1.1 的 CI 链接属于历史版本，本次运行证据单独记录。

### 自动检查

| 范围 | 通过数量 | 本轮重点 |
| --- | ---: | --- |
| 真实 HTTP 桥接 | 22 | 满仓交易、黄金与交易上限、税率与忙碌城守、招募费用及两类俘将占位、多城经营范围、跨重启回执 |
| 原生地图 | 24 | 继续验证相机、拖动/缩放、隐藏任务据点和行军语义 |
| 城池/战斗表现 | 31 | 继续验证建筑、军令与回合表现、窄屏日志布局 |
| 客户端 | 71 | 继续验证布局、地图状态保持、命令顺序、持久未确认请求与重连 |
| 原生城池事务 | 79 | 市场数量实时预览和提交、城守/税率、客栈、等待回执与刷新、电脑/窄屏和事务奖励换行 |
| **总计** | **227** | 根代理独立执行并确认通过 |

Godot 导入通过；构建脚本在导入前生成 `build/.gdignore`，避免递归导入此前导出的资源。CCGS 按 minimal 工作流显式执行验证；本地辅助资料未启用 hook 或 watcher，且不进入 Git 提交或导出包。

### 实际网页观察

IAB 浏览器实际加载 Godot WebAssembly 客户端，在 1280×720 / DPR 2 与 390×844 / DPR 1 完成三类经营界面和事务入口操作。这是浏览器窄屏验证，尚未进行真实 iPhone Safari 或多点触控测试。

使用独立合法虚构存档设置市场 2 级、客栈 2 级、招贤馆 4 级与民房 2 级。观察并经权威快照核对：

- 满仓粮草 10000 / 上限 10000，黄金 50005。输入 `999999` 时，实时成交预览和提交数量收敛到 50005；买入后粮草 60005、黄金 0，资源完整超仓入库。随后卖出 10000，粮草 50005、黄金 10000。操作后面板更新实际余额。
- 客栈打听不扣黄金，显示徐晏（3 级、3000 黄金）和夏松（2 级、2000 黄金）。招募徐晏后黄金 7000、已用房间 3 / 4、将领列表 3 人，属性来自原规则。
- 任命林朔为城守，面板显示城外生产和建设系数 1.48；税率调整为 30%，民心目标 70、显示黄金收入 0.84 / 分钟。
- 后端快照 revision 7 确认上述交易、招募、任命与税率已保存。重新加载后仍显示同一进度（粮草 5.0 万、黄金 7009；期间正常时间收入继续结算）。
- 窄屏市场、城守/税率、客栈均可滚动操作；事务菜单完整容纳入口，任务描述与奖励换行。浏览器 error/warn 日志为空。

截图保留于 `docs/screenshots/management-*.jpg`，包括电脑与窄屏三类表单、事务菜单、城池和将领表。本轮测试没有读取或覆盖玩家原网页存档，`.local/play` 新城进度保持独立；虚构经营存档仅验证操作与规则衔接，不作为自然成长节奏或经济平衡结论。

### 构建与桌面运行边界

官方 Windows 与 Web 模板均导出成功，包内包含 Node Windows 24.21.0、规则服务、游戏资源与许可证，规则快照保持 `c7674df45b9595405e57907524e737e633b0ff63`。本次产物清单：

| 文件 | 字节数 | SHA256 |
| --- | ---: | --- |
| ThreeKingdoms-Godot-v0.2.0-Windows-x64.zip | 86844832 | `d479679ea49c4e15ba17ddce66a97c591116e216853fd6109df99f81eb1df3ff` |
| ThreeKingdoms-Godot-v0.2.0-Web-preview.zip | 59004695 | `f4175dd8d0d24de44a9db50d7636c1118b85556533df35fc66d637bcb653b8cc` |

`build/build-manifest.json` 与 `SHA256SUMS.txt` 同时生成。canonical runtime hash 仍为 `432f9fea6359c18a8d1e2655b09f97770718c3e676501c602c7897afd906a8b4`，原网页仓库 HEAD 不变、工作区干净，没有修改或部署原 Pages。

本机非 headless Godot 客户端已启动，日志确认 OpenGL / Apple M1 和本地规则服务就绪，未出现脚本错误。macOS 原生桌面窗口已实际观察：城池场景与经营入口可见，市场、城守/税率和客栈三个面板均只读打开检查，未执行交易或更改桌面存档；原生截图保留为 `docs/screenshots/management-city-native.jpg`。导出成功、headless 启动、人工桌面交互试玩和长期体验分别记录。

### 0.2.0 发布与 Windows 实际启动

[v0.2.0 预览发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.2.0) 源码与标签均指向 `aa963a8d7584103595983896d8681d2b59e8bfc1`。GitHub 上两个 ZIP、`build-manifest.json` 与 `SHA256SUMS.txt` 四个资产的 digest 均与本地产物一致。

[Windows CI 运行](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37467149603) 在同一提交完成并全绿：真实桥接检查、Godot 导入与原生脚本检查、源码客户端启动以及 `Verify exported Windows executable` 均 success，CI 亦确认上述 227 项全部通过。发布包步骤从正式发布下载 Windows ZIP，核对 SHA256，解压后直接运行 `ThreeKingdoms.exe --headless -- --smoke`，连接随包本地规则服务，收到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`。这确认正式导出包可以启动并载入权威状态与地图，不等于 Windows 人工长局或 Steam 成品验证。

Steamworks、公开账号/共享世界、百人压力测试、真实手机触控、Windows 人工长局、控制器与 Steam Deck 均未验证。原游戏完整名将/招降、联盟、计谋、其它城池管理及正式美术继续迁移；PC 开发后续顺序见 [PC 工作流](PC-GAMES.zh.md)。

### 本地图谱

沿用 `extract . --code-only --exclude '.claude/**' --exclude 'docs/engine-reference/**'`，再 `cluster-only . --no-label`。本轮刷新后为 553 节点、1662 边、29 社区。没有外部语义提取、上传、watcher 或 hooks。Graphify 0.9.76 未识别 `.gd`，引擎 IIFE 覆盖亦不完整；原生界面关系继续核对源码和真实 SceneTree，图中缺少节点不代表没有依赖。

![0.2.0 电脑市场与满仓入库预览](screenshots/management-market-desktop.jpg)

![0.2.0 手机市场](screenshots/management-market-mobile.jpg)

![0.2.0 手机城守与税率](screenshots/management-governance-mobile.jpg)

![0.2.0 手机客栈招募](screenshots/management-inn-mobile.jpg)

![0.2.0 手机事务入口与奖励换行](screenshots/management-transactions-mobile.jpg)

![0.2.0 macOS 原生桌面城池与经营入口](screenshots/management-city-native.jpg)

## 0.1.1 历史验证记录

2026-10-06，Godot `4.7.2.stable.official.ed1daf0bf`，标准版 GDScript。

0.1.1 修正变量字体的整数轴标签，实际渲染坐标确认字重 500；新增直接读取 TextServer 字体坐标的回归检查。初版建设/行军/战斗链路截图保留，当前新城与手机截图已更新为 0.1.1。

### 已完成

- 原仓库 HEAD `c7674df45b9595405e57907524e737e633b0ff63`，工作区干净；没有修改或部署原 GitHub Pages。
- 15 个真实 HTTP 桥接集成用例通过：CAS 并发、重复编号回执跨重启、只读时间投影不重复结算、建筑/训练/真实混编行军、战斗胜利及一次结算、随机加速不重抽、存档迁移/损坏保护、Origin/token/文件隔离。
- 24 个地图检查通过：屏幕/世界坐标、相机边界、拖动阈值、锚点缩放、触屏手势、分区配置、隐藏未来任务据点、行军/驻扎时间语义。
- 31 个城池/战斗表现检查通过：实际建筑等级、军令转发、回合事件动画、旧回合不重复播放、真实主题下窄屏双列按钮不重叠、日志布局。
- 71 个客户端检查通过：1280 与 390 宽度、1280×720 的高度/页脚/侧栏滚动、手机军队末尾按钮可达、资源更新保持地图实例和视角、战斗命令依次使用新 revision 与 sourceCity、持久 pending、同 authority 原编号重试、另一存档禁止重放、401 与请求在途重连、成功清回执、409 刷新。
- macOS 实际运行 Godot 场景并连接自动启动的本地规则服务，收到 `GODOT_SMOKE_OK`，4096 个地图格来自原规则。
- 官方 Windows 与 Web 模板导出成功；打包包含 Node Windows 24.21.0、规则服务、完整资源、许可证和校验清单。下载工具先验证官方 SHA512/SHA256。
- 实际 IAB 浏览器运行 WebAssembly 原生客户端；1280×720 / DPR 2 与 390×844 / DPR 1 验证。修复 Web 高分屏逻辑尺寸、较矮窗口侧栏溢出和手机军队入口不可达。点选、拖动、滚轮缩放、礼包领取、民房建设、配兵出征与真实到达倒计时已操作。战场重新加载恢复，连续两回合战斗胜利自动结算；战报确认损失弓箭兵 2、幸存 998、实际入库粮草 429 / 木材 117，以及俘虏士兵。控制台未出现脚本错误。

### 发布验证

Windows GitHub Actions 源码验证通过：[运行记录](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37421609588)。从本次发布下载 Windows ZIP、核对 SHA256、解压、直接启动导出的 `ThreeKingdoms.exe --headless -- --smoke`，实际运行成功并连接随包规则服务，收到 `GODOT_SMOKE_OK`：[发布包运行记录](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37421796832)。导出成功和 headless 启动不等于 Windows 桌面交互试玩已完成。

### 测试边界

浏览器战斗使用本仓库 `.local/qa-web` 的虚构进度：校场与弓兵由合法测试存档导入，用于检查 UI→规则→战场→战报链路，不作为新手成长速度或资源平衡结论。没有读取、导入或覆盖玩家原网页存档。

尚未进行真实 iPhone Safari 多点触控、Steamworks、百人压力测试、公网账号/共享世界部署或自然长局平衡测试。程序绘制美术为迁移试玩资源，原游戏其它界面仍需继续迁移。

### 本地图谱

沿用 `extract . --code-only --exclude '.claude/**' --exclude 'docs/engine-reference/**'`，再 `cluster-only . --no-label`。553 节点、1667 边、32 社区，无外部语义提取、上传、watcher 或 hooks。

Graphify 0.9.76 当前未识别 GDScript `.gd`；生成的图主要覆盖规则快照与 Node 桥接，原引擎 IIFE 内部仍覆盖不足。Godot 场景关系以 `scenes/main.tscn` 与 `src/*.gd` 源码、真实 SceneTree 验证为准，图中不存在节点不代表没有依赖。

![实际地图拖动和缩放](screenshots/map-desktop.jpg)

![手机战斗布局与恢复](screenshots/battle-mobile.jpg)

![实际战损和入库战报](screenshots/report-mobile.jpg)

![0.1.1 新城预览](screenshots/new-city-preview.jpg)

![0.1.1 手机字体和布局](screenshots/new-city-mobile.jpg)
