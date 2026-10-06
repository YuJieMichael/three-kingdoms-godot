# 0.6账号联机基础验证

2026-10-06，Godot4.7.2、本机Node24.19.0（Windows包Node24.21.0），版本0.6.0-dev.1。故事007为 **In Progress**：账号、数据库和部署代码已完成，本地已验证；正式Supabase游戏项目、域名与持续在线Node主机尚未开通，不能标为公网完成。原three-kingdoms/Pages保持不变。

## 已完成的实现

独立仓库保存0.5检查点dee68fa，并整合远端声音、菜单和对话工具为e5f5c6c，已推送。0.6增加管理员开通的邮箱账号登录、本人房间列表与原城池恢复。Supabase用户独立getUser核验，房间访问必须同时匹配已绑定账号；恢复密钥不能替代云账号。跨标签换账号后，旧请求固定原X-Expected-Account条件，不会替新账号建房、使用其席位或退出其Cookie。

私有game_private表启用RLS并撤销客户端角色访问，后台专用Postgres会话持有世界advisory lock；世界、账号绑定与回执同一事务提交。COMMIT确认丢失、CAS冲突、连接断开或锁丢失后关闭缓存读写，进程重启加载已提交世界。上线入口不允许测试认证/JSON存储回退；提供Caddy HTTPS、systemd、Docker、健康检查、单实例重启与受保护备份恢复。

## 根代理最终检查

| 范围 | 通过 | 证据 |
|---|---:|---|
| Node私服/共享/房间/云账号/配置/备份/真实PG集成 | 97 | .local/online-node-final.log，0失败/取消/跳过 |
| Godot SceneTree客户端、地图、管理、输入、共享、房间、表现与云入口 | 1284 | .local/online-godot-final.log，干净导入，全部退出0 |
| 实际cloud-lobby HTML脚本，隔离DOM/HTTP与五个共享cookie窗口 | 19 | .local/online-final-cloud_lobby_html.log；不等同浏览器渲染 |
| 合计本地自动检查 | 1400 | 各类别计数分别保留 |
| 服务器ZIP/文件同步/秘密排除、解包生产依赖安装与配置检查 | 128 | .local/online-server-package-audit.log；--check返回networkVerified=false |

PG测试运行真实临时PostgreSQL17.10，包含双连接抢锁、并发容量、角色/RLS、COMMIT回执丢失、连接终止、备份恢复与进程重启。云HTTP集成通过本机fake Supabase REST验证登录/独立getUser、过期刷新、退出、错误身份、provider离线，以及离线战斗获胜、掠夺扣账与返城交付只发生一次。**未用真实Supabase Auth或云数据库替代本地fixture**。

独立只读安全复核通过：HTTP/config/backup19、真实PG12、Godot云API/UI123，均0失败；这些是重复复核，不额外加进1400。原跨标签P2已复现、修复并独立确认。Caddy官方2.11.7实际配置validate通过；Docker镜像和systemd启动仅完成静态检查，未执行部署。

## 实际浏览器观察

最终Web导出、本机临时PG与模拟Auth服务上，实际完成Alice登录、建2人房、退出后重新登录找回同一席位。另一个标签切成Bob后，Alice原标签刷新被拒绝并清除旧席位；Bob仍能刷新自己的房间。恢复原Alice后，HTML进入最终Godot Web城池，联机弹窗显示本人账号及原房间。1280×720和390×844均观察，窄屏用T→Tab→Enter进入Godot大厅；本轮窄屏Godot warn/error日志为空，不是实际手机触控测试。

截图无真实账号或房间秘密：account-lobby-final-060.png、account-web-city-final-060.png、account-godot-lobby-final-060.png，以及对应390-final截图。临时标签、模拟会话与PG预览进程已结束；原私人试玩、0.5房间服务和玩家进度保持。

## 最终本地包

Windows与Web PCK已按最终账号保护源码导出；随后只同步rule-service/bridge/README.md并重打ZIP，PCK未改变。服务器包独立构建，只包含所需程序、Web导出、SQL迁移和部署文档，未带node_modules、PG开发二进制、玩家存档、账号密码或.env。

| 文件 | 字节数 | SHA256 |
|---|---:|---|
| ThreeKingdoms-Godot-v0.6.0-dev.1-Windows-x64.zip | 87232488 | `3ada898ccec9bb3239a2c318d184a06b2f5b6d8c575c41179c1fe5a0ee821b48` |
| ThreeKingdoms-Godot-v0.6.0-dev.1-Web-preview.zip | 59389982 | `99273652dfce3b56f6a967466c4fee5da78149eb620a2fca86b175993780a0fc` |
| ThreeKingdoms-Server-v0.6.0-dev.1.zip | 24383304 | `9936d9d770557da29cb299d36960b2f6049b31dfc0fa7940723de1f7dae5ed2a` |

上表为本地包，无0.6公开Release。独立最终包审计1742项通过：静态496、macOS加载两份最终编译PCK1208、包内实际HTML脚本38。各PCK实际编译main与解压包HTTP完成登录、建房、canonical setTax一次提交、退出清UI、重登恢复原席位与税率；这里为本机模拟Supabase REST与隔离JSON存储，未使用实际Supabase/PG。最终PCK保留声音、对话与账号保护；两包59份规则服务文件逐字节匹配最终源码。报告为.local/cloud-package-audit-060-axck1hsi/final-report.json。

Windows EXE未在Windows实际执行，本机PCK检查不能替代该结论；Steamworks、百人负载和跨电脑实际玩家验收未进行。

测试fixture管理员连接补上idle error监听，避免embedded-postgres的退出hook先关库导致测试预览退出报未监听57P01；生产存储fail监听保持。真实PG12项再次通过，预览启动/健康检查/SIGTERM已观察正常signal退出（vendor hook为143）；不是生产部署验收。首轮Windows CI的配置测试使用POSIX固定路径而失败，已改为平台原生绝对路径并复测；最终CI另核对。

## 外部配置待完成

等待用户选择Supabase组织，然后查询费用并取得确认后新建独立游戏项目；当前连接的其他业务数据库未写入。持续运行的Node另需服务器/容器托管账号、域名和管理员账号配置。配置后需真实Auth/数据库、HTTPS/自动重启、备份恢复与跨电脑验收，才能完成故事007。

Graphify按原code-only/exclude标记本地刷新，1102节点、2957边、58社区；不上传、不加watcher/hook。SQL因缺少tree_sitter_sql未提取，.gd仍不覆盖；验证以源代码和运行结果为准。

## Windows与Linux源码CI

最终代码提交 `4936de9e6987e2f69fa74ed0ac88c4d64371b7fd` 的 [GitHub验证](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37518089341) completed/success。Windows HTTP/config/backup83项通过、2项按平台跳过（85总例）；Godot SceneTree1284与HTML脚本19项通过，源码启动返回 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`。Linux真实Postgres12项通过、0跳过。源码CI不等于导出Windows EXE验证；本轮 `Verify exported Windows executable` 因非Release触发而跳过。此记录之后只补充验收文档，没有改生产源码或本地包。
