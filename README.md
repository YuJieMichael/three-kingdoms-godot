# 三国城志 · Godot

Godot 4.7.2＋GDScript 的独立迁移试玩，当前版本 **0.3.0**，新增可配置电脑输入与地图键盘导航。面向 Windows 和网页，Steamworks 在客户端验证后接入。

原 [three-kingdoms 仓库](https://github.com/YuJieMichael/three-kingdoms) 与 [网页版](https://yujiemichael.github.io/three-kingdoms/) 保持不变。本仓库从 `c7674df45b9595405e57907524e737e633b0ff63` 保存规则快照，不直接同步或部署原仓库。

## 试玩

从 [v0.3.0 预览发布](https://github.com/YuJieMichael/three-kingdoms-godot/releases/tag/v0.3.0) 下载独立 Windows/Web 包。实际原生与网页输入已验证，四项发布资产 digest 与本地一致，正式 Windows 发布包下载、校验与启动 CI 通过。独立包使用方式：

- **Windows-x64**：完整解压，双击 `ThreeKingdoms.exe`。引擎资源和本地规则服务均已包含，无需另装 Godot 或 Node。
- **Web-preview**：完整解压，Windows 双击 `StartWeb.cmd`；看到服务就绪后打开 `http://127.0.0.1:17338/`。macOS/Linux 安装 Node 后运行 `./start-web.sh`。不能直接双击 HTML，也没有替换原 GitHub Pages。

进度自动保存。点击“存档”可导入原网页版导出的 JSON，也可导出用于备份。Windows 客户端和网页试玩各有独立进度目录；同时体验同一份进度需连接同一个正在运行的规则服务。该桥接服务仅用于本地试玩，尚未提供账号、公开共享世界或跨设备云同步。

## 当前内容

- 可配置电脑输入：WASD / 方向键移动大地图，`=` / 小键盘 `+` 放大，`-` / 小键盘 `-` 缩小，H / Home 定位主城；1–5 分别切换城池、大地图、军队、将领和战报，T 打开事务、O 存档、K 按键设置。打开弹窗或编辑文字时暂停游戏快捷键；Tab、Enter、Esc 保留原生界面操作。
- 按键设置允许改键、显示冲突并恢复默认，单独在本机保存；配置损坏回退默认，保存失败保留原绑定，游戏进度不受影响。设置按钮和事务入口仍可用鼠标与触屏打开。
- 原生连续地图：64×64 规则世界、鼠标拖动、锚点缩放、触屏手势、城池旗帜、行军路线和到达时间。后续各州扩容需要迁移规则坐标与存档；地图分区目前是可替换的试玩配置。
- 原生城池、建筑建设和升级、城外资源、训练、研究、宝物和加速、当前任务及十阶礼包领取。
- 市场交易、城守与税率管理、客栈招募：显示既有规则的费用与限制，超额交易数量按实际可交易数量收敛，满仓仍可买入并预览超仓入库；任命与调税显示真实生产、建设和民心影响；免费打听游士后按黄金和招贤容量招募。操作回执后刷新实际余额与人员状态。
- 实际部队的行军、驻扎与召回；原生战场、全军/单队命令、每回合移动与伤亡反馈、战报。
- 同一套既有规则负责费用、解锁、队列、行军和结算；回执持久化、重连核对、重复操作去重及版本冲突处理。
- 电脑与窄屏布局；网页高分屏按逻辑像素适配。

当前客户端仍处于迁移试玩阶段。原游戏的联盟、计谋、完整名将/招降、安抚祭祀等其余城池管理界面仍需继续迁移。当前界面采用程序绘制的场景和图标，后续可以换成正式美术资源；各州扩容、账号共享世界与 Steamworks 也尚未接入。

本轮原有 227 项检查与新增输入 255 项检查全部通过，共 482 项。macOS 原生窗口已实际验证按键冲突、重绑后重启仍生效、恢复默认、地图方向键移动、小键盘缩放和回城。最终网页导出已验证文字编辑隔离、弹窗关闭后立即按键切页、地图平移/缩放/回城及 390×844 窄屏设置入口与滚动；控制台 warn/error 为空。Windows/Web 0.3.0 已发布，Windows CI 下载正式 ZIP、核对 SHA256、解压并启动导出的客户端，收到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`：[运行记录](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37472454474)。0.2.0 的经营操作及 Windows 启动 CI 作为历史记录保留。尚未进行 Windows 人工长局、真实 iPhone 多点触控、手柄、性能 FPS 或 Steamworks 验证。详细证据见 [验证记录](docs/QA.zh.md)。

## 开发

安装标准版 **Godot 4.7.2 stable**（GDScript）和 Node。用 Godot 导入 `project.godot`。通过环境变量 `TK_NODE` 指定 Node 完整路径，运行项目即可自动启动本地规则服务；也可在连接窗口填写服务地址。

```sh
node --test tests/bridge.test.cjs
godot --headless --path . --editor --import
godot --headless --path . --script tests/world_map_test.gd
godot --headless --path . --script tests/battle_view_test.gd
godot --headless --path . --script tests/client_test.gd
godot --headless --path . --script tests/management_test.gd
godot --headless --path . --script tests/input_test.gd
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

[架构](docs/ARCHITECTURE.zh.md)、[桥接协议](bridge/README.md)、[验证记录](docs/QA.zh.md)、[PC 开发工作流](docs/PC-GAMES.zh.md)、[第三方许可证](THIRD_PARTY_NOTICES.md)。GitHub Actions 验证 Windows 上的规则、原生脚本和启动；发布工作流还可验证导出的 Windows 可执行文件。
