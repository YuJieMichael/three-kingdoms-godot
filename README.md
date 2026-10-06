# 三国城志 · Godot

Godot 4.7.2＋GDScript 的独立迁移试玩，当前版本 **0.2.0**。面向 Windows 和网页，Steamworks 在客户端验证后接入。

原 [three-kingdoms 仓库](https://github.com/YuJieMichael/three-kingdoms) 与 [网页版](https://yujiemichael.github.io/three-kingdoms/) 保持不变。本仓库从 `c7674df45b9595405e57907524e737e633b0ff63` 保存规则快照，不直接同步或部署原仓库。

## 试玩

从 [Releases](https://github.com/YuJieMichael/three-kingdoms-godot/releases) 下载独立包：

- **Windows-x64**：完整解压，双击 `ThreeKingdoms.exe`。引擎资源和本地规则服务均已包含，无需另装 Godot 或 Node。
- **Web-preview**：完整解压，Windows 双击 `StartWeb.cmd`；看到服务就绪后打开 `http://127.0.0.1:17338/`。macOS/Linux 安装 Node 后运行 `./start-web.sh`。不能直接双击 HTML，也没有替换原 GitHub Pages。

进度自动保存。点击“存档”可导入原网页版导出的 JSON，也可导出用于备份。Windows 客户端和网页试玩各有独立进度目录；同时体验同一份进度需连接同一个正在运行的规则服务。该桥接服务仅用于本地试玩，尚未提供账号、公开共享世界或跨设备云同步。

## 当前内容

- 原生连续地图：64×64 规则世界、鼠标拖动、锚点缩放、触屏手势、城池旗帜、行军路线和到达时间。后续各州扩容需要迁移规则坐标与存档；地图分区目前是可替换的试玩配置。
- 原生城池、建筑建设和升级、城外资源、训练、研究、宝物和加速、当前任务及十阶礼包领取。
- 市场交易、城守与税率管理、客栈招募：显示既有规则的费用与限制，超额交易数量按实际可交易数量收敛，满仓仍可买入并预览超仓入库；任命与调税显示真实生产、建设和民心影响；免费打听游士后按黄金和招贤容量招募。操作回执后刷新实际余额与人员状态。
- 实际部队的行军、驻扎与召回；原生战场、全军/单队命令、每回合移动与伤亡反馈、战报。
- 同一套既有规则负责费用、解锁、队列、行军和结算；回执持久化、重连核对、重复操作去重及版本冲突处理。
- 电脑与窄屏布局；网页高分屏按逻辑像素适配。

当前客户端仍处于迁移试玩阶段。原游戏的联盟、计谋、完整名将/招降、安抚祭祀等其余城池管理界面仍需继续迁移。当前界面采用程序绘制的场景和图标，后续可以换成正式美术资源；各州扩容、账号共享世界与 Steamworks 也尚未接入。

本轮 227 项本地检查通过，实际浏览器在电脑窗口与 390 像素窄屏完成交易、招募、任命、调税和重新加载验证；macOS 原生窗口的城池与三类经营面板也已只读打开观察。Windows/Web 试玩包已导出；0.2.0 Windows 发布包实际启动验证待发布后 CI 完成，不能以导出成功替代运行结果。详细证据见 [验证记录](docs/QA.zh.md)。

## 开发

安装标准版 **Godot 4.7.2 stable**（GDScript）和 Node。用 Godot 导入 `project.godot`。通过环境变量 `TK_NODE` 指定 Node 完整路径，运行项目即可自动启动本地规则服务；也可在连接窗口填写服务地址。

```sh
node --test tests/bridge.test.cjs
godot --headless --path . --editor --import
godot --headless --path . --script tests/world_map_test.gd
godot --headless --path . --script tests/battle_view_test.gd
godot --headless --path . --script tests/client_test.gd
godot --headless --path . --script tests/management_test.gd
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
