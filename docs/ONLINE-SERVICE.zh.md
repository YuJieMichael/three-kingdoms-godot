# 账号联机与持续运行服务

0.6.0-dev.1 是账号联机的开发预览。原 three-kingdoms 仓库与 GitHub Pages 保持不变。本仓库的账号、数据库与 Node 部署是独立服务。

## 当前边界

账号接口使用 Supabase Auth，世界数据使用 Supabase Postgres，现有 Node canonical 规则服务负责行军、自动战斗与返程入库。真实游戏云项目已创建并完成数据库与 Auth 基础配置；实际账号登录、服务连接、域名与公网主机尚未验证。代码本地验证不能代替跨电脑验收。

2026-10-06 用户在独立 Free 组织「山河策工作室」（`mwctnnafccwgcezatckw`）内创建了游戏项目「山河策」（`biembbkyghflivkmeecl`），区域 Canada (Central)，网页显示 NANO，SQL 返回 Postgres 17.11。通过已登录的 Dashboard 建立并核验 `game_private.room_worlds`：RLS 已开启，客户端策略为 0，PUBLIC、anon、authenticated 均无访问权限。Data API 保持关闭；Auth 邮箱密码入口开启，公开注册与匿名登录关闭，邮箱确认开启。用户已创建3个游戏账号，逐个核验邮箱均已确认，并加入本机私密内测名单；邮箱与UID不写入本说明。

用户选择「暂不付费，先本机联调」，没有开通付费托管或独立 IPv4。现有 Supabase 连接器仍无新组织权限，本轮配置使用网页；原房产业务组织与项目未修改。Node 服务先在本机运行；Supabase 项目本身不会自动托管本仓库的 Node 进程。

## 本次本机联调入口

私密启动包装脚本位于 `.local/start-supabase-local.mjs`，配置位于 `.local/supabase-local.env`，均不进入 Git 或导出包。项目 URL、publishable key、实际 session pooler 5432 地址和3个已确认账号的内测邮箱已写入配置；尚缺已有数据库密码。密码只在本机填写，不能发到聊天或提交仓库。

配置支持在 `DATABASE_PASSWORD` 填原始密码并自动处理 URL 编码，也支持直接填写包含已编码密码的完整 `DATABASE_URL`；两者不能同时提供实际密码。将同一个内测账号邮箱填入 `TK_ALLOWED_EMAILS`，并在 Dashboard 的 Authentication → Users → Add user → Create new user 中亲自设置游戏登录密码、确认并提交。该管理员表单默认勾选 Auto confirm user，且明确不发送确认邮件；请只用于管理员确认归属的内测账号。

启动需要 Node 24：

```sh
node .local/start-supabase-local.mjs --check
node .local/start-supabase-local.mjs
```

入口固定为 `http://127.0.0.1:17345/lobby`，仅监听本机，使用真实 Supabase Auth、已确认邮箱与允许名单。状态目录为 `.local/cloud-real-060`，数据库 namespace 为 `shanhece-local-real`；不覆盖 17339 私人试玩或其他演练进度。使用独立的 `build/brand-preview` 完整 Web 导出。TLS 证书验证保持开启，数据库断连或失锁时退出，不回退本机 JSON 或测试账号。

`--check` 只检查本机配置与资源；本轮 23 项密码编码、连接限制和配置 fixture 通过，私密包装脚本经只读审查。真实网络连接尚未启动，不能将该检查当作登录或存档成功。正常启动会在真实数据库创建该 namespace 的初始记录；后续验收需实际登录、建房、保存、停止并重启服务，再核对房间与离线结算。

## 玩家入口

网页访问游戏服务器的 `/lobby`，输入管理员开通并已确认邮箱的内测账号。登录后可点击“我的房间”恢复自己的城池，或创建1–8人房间、用邀请码加入朋友的房间。同账号重复加入同一房间会恢复原席位，满员时也可返回已有城池。

桌面端从“联机”或“菜单 → 连接”填写 HTTPS 服务根地址，登录后选择自己的房间。开发预览仍支持原本的本机 HTTP 演练入口。在线房间不接受恢复密钥替代账号；原本机房间的恢复方式保留。

房间起点继续使用同等备战演练配置，沿用原兵种、经济、战斗和服务器结算规则。关客户端不会暂停行军。Node 重启后会读数据库并补结算；账号会话需要重新登录，原房间和城池保留。

## 后台配置

1. 在选定组织中创建独立 Supabase 游戏项目。关闭公开自助注册，通过 Auth 管理界面创建或邀请2–8名内测玩家，并确认邮箱。将这些邮箱写入 `TK_ALLOWED_EMAILS`。
2. 在该项目执行 `supabase/migrations/*_private_room_state.sql`。`game_private.room_worlds` 为非公开世界表，启用RLS，撤销PUBLIC、anon、authenticated访问权限；不要将game_private加入Data API的exposed schemas。应用不直接从浏览器写资源或兵力。
3. 获取该项目的publishable key、Auth URL和后台Postgres连接。后台数据库连接使用迁移/表所有者，作为服务器秘密；日后可配置只访问game_private的专用后台数据库角色。不能把数据库口令或secret/service_role key写进客户端、PCK、页面或Git。
4. 复制 `deploy/cloud.env.example` 为 `/etc/three-kingdoms/cloud.env`，仅服务器管理员可读（0600）。填写 `TK_PUBLIC_ORIGIN`、`SUPABASE_URL`、`SUPABASE_PUBLISHABLE_KEY`、`DATABASE_URL` 和 `TK_ALLOWED_EMAILS`。DATABASE_URL中的口令需百分号编码。

数据库必须使用直连或**session pooler（5432）**，不能用transaction pooler（6543）。本服务用专用连接持有世界独占锁；同一namespace只运行一个规则进程。TLS验证始终开启，无法确认数据库证书时启动失败，不降级为不验证证书。若项目使用独立CA，将项目Dashboard下载的可信证书保存到服务器，通过 `NODE_EXTRA_CA_CERTS` 指定；不要使用关闭TLS验证的环境变量。

Node使用24版本。部署包解压到 `/opt/three-kingdoms` 后运行：

```sh
npm ci --omit=dev --ignore-scripts
node --env-file=/etc/three-kingdoms/cloud.env scripts/start-cloud.mjs --check
```

`--check` 只检查配置和完整Web资源，不表示已连上数据库或完成公网部署。正式启动不接受测试认证或本机JSON存储回退。

## 持续运行与HTTPS

Linux可安装 `deploy/three-kingdoms.service`，创建专用 `three-kingdoms` 系统用户，确认Node位于 `/usr/bin/node`，将项目放在 `/opt/three-kingdoms`。systemd配置自动重启、独立状态目录和只读程序目录。配置文件、主机账户和服务安装由部署目标提供后执行。

Caddy使用 `deploy/Caddyfile`，将环境变量 `TK_GAME_DOMAIN` 设为实际域名并正确配置DNS/80/443端口。代理转发到本机3080；公网仅开放HTTPS入口。Node的3080不直接暴露公网。

可选容器：

```sh
docker build -f deploy/Dockerfile -t three-kingdoms:0.6.0-dev.1 .
docker run -d --name three-kingdoms --restart unless-stopped --stop-timeout 30 \
  --env-file /etc/three-kingdoms/cloud.env \
  -e TK_HOST=0.0.0.0 -e TK_DATA_DIR=/tmp/three-kingdoms \
  -p 127.0.0.1:3080:3080 three-kingdoms:0.6.0-dev.1
```

容器包只安装生产pg依赖，不包含开发Postgres二进制或私人进度。Web资源必须为该开发版完整导出，位于 `build/web-online`。HTTPS代理和Node必须使用同一网页/API根地址。`GET /readyz` 返回存储与结算是否可用，失锁/断连后返回503；不泄露身份或凭据。

## 备份和恢复

完整世界、成员绑定、兵力、资源和操作回执在同一个数据库事务提交。备份包含私有房间凭据，只存到服务器私有备份目录，不放进Web资源或Git。备份可在服务器运行时读取一个完整已提交版本；恢复必须先停止规则服务，并保留当前版本备份。

```sh
node --env-file=/etc/three-kingdoms/cloud.env scripts/cloud-backup.mjs --out /var/backups/three-kingdoms/world-2026-10-06.json
```

脚本以0600创建新文件，已有同名备份不会覆盖，禁止将备份放进Web资源或build目录（包括符号链接别名）。应复制到受保护的异地主机或对象存储，并定期在隔离项目演练恢复；本轮不会自动配置云存储或定时任务。

```sh
# 停止服务后，将备份恢复到空namespace；不会自动覆盖已有世界。
node --env-file=/etc/three-kingdoms/cloud.env scripts/cloud-backup.mjs --restore /var/backups/three-kingdoms/world-2026-10-06.json
# 若确实要替换已有世界，先保存当前备份，再显式加 --replace。
```

恢复核对文件校验和、namespace与canonical存档结构。服务仍持有该世界独占锁时恢复会被拒绝。数据库COMMIT回执丢失后，进程停止读取/写入旧缓存；重启从已提交回执恢复，同编号命令仍按原规则幂等核对。

## 内测账号与会话

账号登录经Supabase密码接口，再独立向Auth服务器核对用户；不信任客户端填写的accountId或可编辑user_metadata。每次受保护请求继续验证账号。房间API同时要求本人账号会话与该房间访问令牌，并核对持久化accountId。

已验证页面的请求同时携带 `X-Expected-Account` 账号一致性条件。另一标签切换账号后，旧页面的建房重试、房间列表、进入游戏和退出会被拒绝并清除旧页面状态，不能采用新账号的席位或退出新账号。这个条件不能替代服务器的Auth验证，也不能赋予城池权限。

密码与Supabase access/refresh token不写数据库或客户端。Node内存保存provider token并序列化刷新，向客户端发12小时上限的不透明会话；网页使用HttpOnly、Secure、SameSite=Strict cookie，原生只在进程内存持有会话。重启需重新登录。当前没有自助注册、找回密码或Steam账号桥接；管理员可在Supabase配置账号。

创建/参与房间默认最多32个世界、每账号4个房间，可通过私有配置修改。请求设有限流；精确校验浏览器来源并拒绝跨站账号请求。初期仅允许名单中的好友进入。

## 文档依据

实现前读取2026-10-06 Supabase changelog，使用当前[Auth getUser说明](https://supabase.com/docs/reference/javascript/auth-getuser)、[Postgres连接说明](https://supabase.com/docs/guides/database/connecting-to-postgres)、[API权限说明](https://supabase.com/docs/guides/api/securing-your-api)与[Caddy代理说明](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)。未启用Graphify上传、watcher或语义后端。
