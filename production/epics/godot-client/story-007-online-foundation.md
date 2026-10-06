# 正式账号与持续运行的联机服务

Status: In Progress
Last Updated: 2026-10-06
Story Type: Integration / UI / Config
GDD: design/game-brief.md
ADR Governing Implementation: N/A — 继续使用现有canonical规则，Supabase负责账号与Postgres持久化，独立Node服务负责结算。
Dependencies: story-006-room-lobby.md — Complete

## 目标

用户选择下一轮1、2、3：保存0.5版本到独立仓库、接入正式账号和数据库、准备并配置持续运行的服务器。原three-kingdoms与Pages保持不变。先完成代码、验证与部署包；新Supabase组织选择、费用确认以及托管账号等待用户提供，未收到答复不创建收费资源或修改其他业务数据库。

## 验收

- [x] 保存并推送0.5检查点，整合远端已合并的音效、菜单和对话工具。
- [x] Web与Godot支持账号登录和自己的房间列表，换客户端登录后恢复原城池；邀请码只能加入空席位，同账号重复加入不新增成员。
- [x] 云端每次受保护操作验证Supabase用户，客户端不能凭昵称、其他城主密钥或伪造账号接管席位；密码、刷新令牌和数据库密钥不进入包或日志。
- [x] Postgres原子保存成员绑定、canonical世界和操作回执，具备单实例排他、断连停止写入、重启恢复及失败重试证据。
- [x] 提供HTTPS反向代理、持续运行、健康检查、受限创建/请求速率、备份恢复与配置检查的可运行部署包。
- [x] 运行有意义的账号/数据库/客户端/现有规则验证，并区分本地验证、真实Supabase及公网部署。
- [ ] 配置独立游戏云项目与部署地址并验证，或明确记录必需的外部配置仍待用户提供，不能将该项标为完成。

## 账号协议

云服务 /auth/config 公布 enabled=true。POST /auth/login {email,password} 返回 {ok:true,sessionToken:<64hex>,user:{id,email}}，同时设置Web HttpOnly SameSite=Strict会话cookie。密码只用于向Supabase密码登录；Supabase access/refresh令牌仅在服务内存，不落盘。POST /auth/logout 清会话；GET /auth/me 验证会话。原生账号会话只在运行内存；Web通过HttpOnly cookie持有不透明会话，不写游戏存档。

云房间请求与游戏API以 X-Account-Session 提供会话（网页也可用同源cookie）；Authorization Bearer仍为已有房间访问令牌，不能替代账号验证。GET /lobby/mine 返回 {ok:true,rooms:[{room,seat,actor,authorityId}]}。POST /lobby/account-resume {roomId} 自动恢复已绑定的本人席位，返回与本机相同的memberSession形状。创建/加入原字段保持不变但额外绑定已验证accountId。云端禁用 /lobby/resume 密钥式恢复，已有本机服务仍保持原有行为。

Supabase文档与2026-10-06 changelog已读取；不使用已弃用的框架adapters，不引入OrioleDB或SQL扩展。

## 状态

组织选择和Node托管目标通过异步问题等待回复；在此期间继续完成全部可独立进行的开发。

## 开发交付与未完成项

0.5检查点 `dee68fa` 与远端音效/菜单/对话合并为 `e5f5c6c`，已推送独立仓库。0.6账号、Postgres与部署代码完成，最终本地HTTP/数据库97项、SceneTree1284项、实际HTML脚本隔离fixture19项，共1400项通过。独立复核未发现阻断开发预览的问题。实际Web已观察登录、建房、退出后恢复原席位、跨标签变更拒绝以及最终Godot Web城池。完整证据见 `production/polish/online-foundation-report-2026-10-06.md`。

真实Supabase游戏项目、域名和持续在线Node主机尚未创建或部署。等待组织选择后查询费用并确认、等待托管目标和管理员账号配置；未修改其他业务项目。该故事继续In Progress，不将本地fake Auth和真实本机PG测试等同公网完成。Docker/systemd部署、Windows EXE实际运行和跨电脑验收未在本轮完成。
