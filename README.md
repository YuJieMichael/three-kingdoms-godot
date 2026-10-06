# 三国城志 · Godot

Godot 4.7.2＋GDScript 的独立迁移试玩，当前本地版本为 **0.5.0 1–8人房间演练**：创建房间、邀请码加入、自己的席位恢复，以及玩家城池、盟友援军、服务器自动战斗与返程入库。0.3.1 大地图更新继续保留。面向 Windows 和网页，Steamworks 与正式公网账号服务在后续接入。

开发分支已接入声音管理、菜单分页和可编辑新手剧情，使用方式与验证见 [表现工具说明](docs/PRESENTATION-TOOLS.zh.md)。游戏内从“菜单”进入声音、按键、引导、存档和连接设置；当前音乐及音效为原创合成示范素材。

原 [three-kingdoms 仓库](https://github.com/YuJieMichael/three-kingdoms) 与 [网页版](https://yujiemichael.github.io/three-kingdoms/) 保持不变。本仓库从 `c7674df45b9595405e57907524e737e633b0ff63` 保存规则快照，不直接同步或部署原仓库。

## 试玩

当前公开版本仍为 [v0.3.1 预览发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.1) 下载独立 Windows/Web 包。实际原生与网页地图已验证，四项发布资产的大小及 digest 与本地一致；0.3.1 正式 Windows 发布包下载、校验与启动 CI 已通过；这些历史结果不代表 0.4.0/0.5.0 的 Windows 实机运行。独立包使用方式：

- **Windows-x64**：完整解压，双击 `ThreeKingdoms.exe`。引擎资源和本地规则服务均已包含，无需另装 Godot 或 Node。
- **Web-preview**：完整解压，Windows 双击 `StartWeb.cmd`；看到服务就绪后打开 `http://127.0.0.1:17338/`。macOS/Linux 安装 Node 后运行 `./start-web.sh`。不能直接双击 HTML，也没有替换原 GitHub Pages。

进度自动保存。点击“存档”可导入原网页版导出的 JSON，也可导出用于备份。Windows 客户端和网页试玩各有独立进度目录；同时体验同一份进度需连接同一个正在运行的规则服务。私人桥接服务仅用于本地试玩。0.4.0 另有独立的本机四账号共享演练，不能将私人存档导入共享世界；公开共享世界和跨设备账号同步尚未接入。

本地 0.4.0 包的共享入口：Windows 完整解压后先运行 `StartPvP.cmd`，再运行 `PlayPvP1.cmd`～`PlayPvP4.cmd`；网页包运行 `StartPvP.cmd` / `start-pvp.sh`，从私有邀请页面选择账号。详情见 [共享演练说明](docs/PVP-REHEARSAL.zh.md)。

0.4.0 的 **1040 项本地检查通过**，实际 macOS/Web 攻防、援军驻扎与召回、战报及返程入库已观察；最终 Windows/Web 包导出和包内规则服务验证通过。此版本尚未公开发布，Windows 可执行文件尚未运行。详见 [共享 PvP 验证报告](production/polish/shared-pvp-report-2026-10-06.md)。

本地0.5.0房间入口：Windows先运行 `StartRooms.cmd`，再运行 `PlayRooms.cmd`；网页包运行 `StartRooms.cmd` / `start-rooms.sh`，打开本机联机大厅。邀请只能申请空席位，自己的恢复密钥才可返回已有城池。请自行保存密钥；未确认登记时保持窗口开启并重试原请求。详见 [房间说明](docs/ROOMS.zh.md)。

0.5.0已完成 **1187项核心本地检查和365项独立包审计**，真实Web/macOS房间、390大厅及战报实际交付已观察；Windows/Web本地包已导出。尚未公开发布或在Windows执行0.5.0 EXE，正式跨电脑后台待配置。见 [房间验证报告](production/polish/room-lobby-report-2026-10-06.md)。

## 当前内容

- 本机1–8人房间：服务器生成城主与独立世界，创建、邀请与满员恢复，重复登记去重、容量并发保护及原子存档。网页与桌面大厅均可使用；正式跨电脑服务尚未配置。
- 本机四账号共享攻防：两组联盟与四座各自保存的城池；派兵掠夺、盟友援军、驻扎召回和行军倒计时。到时由服务器自动交战，战报显示双方幸存、永久损失、伤兵与缴获，返城后显示实际入库。演练兵力与战争状态为虚构预置，沿用原作规则。
- 可配置电脑输入：WASD / 方向键移动大地图，`=` / 小键盘 `+` 放大，`-` / 小键盘 `-` 缩小，H / Home 定位主城；1–5 分别切换城池、大地图、军队、将领和战报，T 打开事务、O 存档、K 按键设置。打开弹窗或编辑文字时暂停游戏快捷键；Tab、Enter、Esc 保留原生界面操作。
- 按键设置允许改键、显示冲突并恢复默认，单独在本机保存；配置损坏回退默认，保存失败保留原绑定，游戏进度不受影响。设置按钮和事务入口仍可用鼠标与触屏打开。
- 原生连续地图：64×64 规则世界、鼠标拖动、锚点缩放、触屏手势、城池旗帜、行军路线和到达时间。后续各州扩容需要迁移规则坐标与存档；地图分区目前是可替换的试玩配置。
- 0.3.1 更新：长行军虚线按视口裁剪，保留两端屏外但穿过屏幕的路线与原始虚线相位；屏外部队及隐藏行军的筛选减少无效动画刷新，短行程在卡顿后仍更新最终抵达位置。远景只遍历城池与任务特征，河流保留原采样格并缩小准备范围，地形样式不变。
- 原生城池、建筑建设和升级、城外资源、训练、研究、宝物和加速、当前任务及十阶礼包领取。
- 市场交易、城守与税率管理、客栈招募：显示既有规则的费用与限制，超额交易数量按实际可交易数量收敛，满仓仍可买入并预览超仓入库；任命与调税显示真实生产、建设和民心影响；免费打听游士后按黄金和招贤容量招募。操作回执后刷新实际余额与人员状态。
- 实际部队的行军、驻扎与召回；原生战场、全军/单队命令、每回合移动与伤亡反馈、战报。
- 同一套既有规则负责费用、解锁、队列、行军和结算；回执持久化、重连核对、重复操作去重及版本冲突处理。
- 电脑与窄屏布局；网页高分屏按逻辑像素适配。

当前客户端仍处于迁移试玩阶段。原游戏的联盟、计谋、完整名将/招降、安抚祭祀等其余城池管理界面仍需继续迁移。当前界面采用程序绘制的场景和图标，后续可以换成正式美术资源；各州扩容、正式跨电脑账号服务与 Steamworks 也尚未接入。

0.3.1 的 **697 项本地与 Windows CI 检查已通过**（原有 482＋新增地图 215），[源码推送 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479201825) 已成功。最终原生与 Web 桌面/390 窄屏已观察地图拖动、远景、缩放、回城及当前任务点侧栏；浏览器 warn/error 日志为空。Windows/Web 已导出并发布，四项资产校验通过；[标签 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479270820) 与 [正式 Windows 包启动 CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37479418934) 均成功，故事 004 已完成。

同条件原生捕获中，总览每次重绘 CPU p95 为 72.376→37.163 ms，正常 64² 地图为 17.543→16.626 ms。CPU 绘制准备减少，但 64² 拖动帧间隔 p95 略升、引擎 draw calls 未下降，快照索引准备更贵；GPU 时间及 Windows/Web 性能未测，四项预算未设定。合成 256²／200 行军不是已扩州或 200 名玩家。完整数值、第一轮回退与原始数据见 [性能报告](production/polish/world-map-report-2026-10-06.md) 和 [复现说明](docs/MAP-PERFORMANCE.zh.md)。

0.3.1 正式 ZIP 经 SHA256 校验后运行导出的客户端，收到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`；headless 启动验证不代替 Windows 桌面人工试玩。尚未验证 Windows 人工长局、真实手机多点触控、手柄或 Steamworks。详细观察与构建证据见 [验证记录](docs/QA.zh.md)。

## 开发

安装标准版 **Godot 4.7.2 stable**（GDScript）和 Node。用 Godot 导入 `project.godot`。通过环境变量 `TK_NODE` 指定 Node 完整路径，运行项目即可自动启动本地规则服务；也可在连接窗口填写服务地址。

```sh
node --test tests/bridge.test.cjs tests/shared-bridge.test.cjs tests/room-bridge.test.cjs
godot --headless --path . --editor --import
godot --headless --path . --script tests/world_map_test.gd
godot --headless --path . --script tests/battle_view_test.gd
godot --headless --path . --script tests/client_test.gd
godot --headless --path . --script tests/management_test.gd
godot --headless --path . --script tests/input_test.gd
godot --headless --path . --script tests/map_render_test.gd
godot --headless --path . --script tests/pvp_api_test.gd
godot --headless --path . --script tests/pvp_ui_test.gd
godot --headless --path . --script tests/lobby_api_test.gd
godot --headless --path . --script tests/lobby_ui_test.gd
godot --headless --path . -- --smoke
```

网页开发：先安装对应 Godot Web 导出模板，导出后用同源服务启动：

```sh
godot --headless --path . --export-release Web build/web/index.html
node bridge/server.mjs --port 17339 --data-dir .local/web --web-dir build/web
```

构建脚本验证官方 Node Windows 24.21.0 下载校验和，导出客户端并生成压缩包、许可证、清单和 SHA256。需要 Godot 对应 Windows/Web 模板和官方 `node-v24.21.0-win-x64.zip`。

```sh
python3 scripts/build.py --godot /path/to/godot --node-win-zip /path/to/node-v24.21.0-win-x64.zip
```

[架构](docs/ARCHITECTURE.zh.md)、[桥接协议](bridge/README.md)、[验证记录](docs/QA.zh.md)、[PC 开发工作流](docs/PC-GAMES.zh.md)、[地图性能复现](docs/MAP-PERFORMANCE.zh.md)、[第三方许可证](THIRD_PARTY_NOTICES.md)。GitHub Actions 验证 Windows 上的规则、原生脚本和启动；发布工作流还可验证导出的 Windows 可执行文件。
