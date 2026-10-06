# 0.5.0 房间与席位恢复验证

2026-10-06。CCGS minimal / dev-story → story-done，故事006。本轮完成独立本机1–8人房间、邀请码加入与自己的城池恢复，保留原经营、兵种及自动结算规则。原仓库和原Pages没有修改。正式后台的选择仍待用户回复，不将已连接的其他业务Supabase项目作为游戏后台。

## 实现与验收

| 验收 | 实现/证据 | 结果 |
|---|---|---|
| 创建1–8人房间、邀请空席位、恢复原城主 | room-bridge测试；真实Web建房/加入/满员恢复；原生加入与重启后恢复 | OBSERVED / PASS |
| 独立房间、稳定身份、各房间互不读取 | room-store/server；HTTP跨房间权限检查；Godot严格actor/authority/room握手 | PASS |
| 原请求重试、容量并发、原子保存 | HTTP并发、回执冲突、重启、rename与目录fsync故障回滚 | PASS |
| 原规则攻防、援军、自动结算与返程 | HTTP真实掠夺、离线定时与回滚；原生援军及实际Web胜利/交付 | OBSERVED / PASS |
| Web/桌面/390大厅与正确会话交接 | lobbyAPI60、lobbyUI80；真实HTML390、GodotWeb390及原生大厅截图 | OBSERVED / PASS |
| 仅本人恢复信息、秘密不混入客户端存储/日志/查询参数 | 独立源码复核及包审计；令牌片段进入游戏后清除；大厅密钥遮蔽 | PASS |
| 自动检查与实际运行记录 | HTTP66、SceneTree1121、实际Web/macOS截图、最终PCK验证 | PASS |
| 独立启动入口与本地Windows/Web包 | 最终包203项新确认，未变后台162项运行证据；启动说明 | PASS |

当前房间服务器仍只绑定loopback。每位城主预置600轻骑、500弓箭、300长枪及同一套备战资源；初始席位交替分入青/赤两盟，后续以原作当前联盟关系为准。该配置明确标注为演练，不是正式新手礼包或经济平衡调整。

## 自动检查

**1187项检查全部通过**，不把下面包审计重复计入核心检查数。

| 检查 | 数量 |
|---|---:|
| 私人桥接HTTP | 22 |
| 四账号共享HTTP | 23 |
| 房间HTTP | 21 |
| world_map | 24 |
| battle_view | 31 |
| client | 236 |
| management | 79 |
| input | 255 |
| map_render | 215 |
| pvp_api | 89 |
| pvp_ui | 52 |
| lobby_api | 60 |
| lobby_ui | 80 |

全套66项HTTP由根代理最终执行，日志 `.local/rooms-http-final.log`。SceneTree先完成1100项检查与隔离smoke，随后实际GUI发现的失败提示修复重新运行相关检查，最终1121项。最终汇总 `.local/rooms-godot-final-complete-summary.json`，补正后两项日志为 `.local/rooms-final-retained-pvp_ui.log` 与 `.local/rooms-final-retained-lobby_ui.log`。旧汇总 `.local/rooms-godot-final-summary.json` 记录修复前计数；不要把其中49/62当作最终PvP/大厅UI数量。`--smoke` 使用独立user目录，收到 `GODOT_SMOKE_OK canonical_revision=0 tiles=4096`，未覆盖真实私人进度。

独立审查发现一个P1：合法JSON空值被当作缺失存档，可能覆盖已有文件。改为仅ENOENT创建新档；null/false/0/空字符串/数组/其他字符串6种无效内容均验证保留原字节并失败关闭。原私人与四账号存档目录同样拒绝用作新房间目录。

实际双网页攻防中还发现一个P2：服务器明确409拒绝后，派遣表单仍显示“正在核定派遣”。最终版显示实际失败原因，保留配兵并恢复允许的按钮；运输未确认时保留原请求编号并禁用重复派遣。等待文案先于信号发送，同步回执保存失败不会被覆盖。UI状态检查和真实main＋GameApi响应回归已覆盖，最终compiledPCK也验证这一流程。

## 实际运行

根代理通过真实浏览器与macOS Godot操作，未用测试存档覆盖既有私人试玩。

- 网页创建3人房间“群雄房间验证”，另一网页加入赤城主，原生客户端加入第三席位青援军。两端均显示同一房间3/3、自己的城池和真实当前联盟关系。
- 原生派出20轻骑援助青城主；网页看见同一部队驻扎，原生召回并自动归队。最终版客户端重启、用自己的恢复信息回到席位3，配兵表单确认可用轻骑恢复600。
- 青城主用300长枪、500弓箭、600轻骑真实掠夺赤城主；服务器自动交战和返回。攻方幸存500弓箭，永久损失195长枪/390轻骑，伤兵105长枪/210轻骑；守方无幸存。战报缴获粮草12000，返程已交付粮草12000。没有手动确认战斗或注入战斗结果。
- 第四名加入者收到满员提示；已有青城主仍可恢复原席位，成员数保持3，原资源与已交付战报保留。首次恢复使用了自动化界面遮蔽后的无效测试值，服务正确拒绝；改用本地演练夹具中对应城主的有效密钥后恢复成功。没有把这个预期拒绝计为成功恢复。
- 最终导出重载后重新恢复青城主，实际读取同一已交付战报。390×844实看HTML大厅，以及Godot事务→联机大厅的滚动布局。Godot窄屏入口用Tab/Enter实际打开；临时视口已复位。最终Web warn/error日志为空。
- 房间测试原生窗口已结束，原私人客户端恢复为青溪城，原生规则服务成功启动；17339私人预览及17342四账号服务保留。17343新房间大厅保持运行。

保留截图：

- `docs/screenshots/rooms-lobby-final-050.png`：最终HTML大厅，无任何成员秘密。
- `rooms-lobby-390-050.png`：HTML390布局。
- `rooms-godot-lobby-390-final-050.png`：最终GodotWeb390大厅、已认证城主及3/3成员。
- `rooms-web-aid-050.png` / `rooms-native-aid-050.png`：两端同一驻扎援军。
- `rooms-web-final-report-050.png`：最终导出版本中同一战报及粮草12000交付。
- `rooms-native-final-recovery-050.png` / `rooms-native-final-return-050.png`：最终原生重启恢复与600可用轻骑。

![最终联机大厅](../../docs/screenshots/rooms-lobby-final-050.png)

## 最终导出与独立包审计

官方Godot4.7.2 stable导出Windows/Web，包含固定校验的官方Windows Node24.21.0、规则服务及游戏资源。最终包：

| 文件 | 字节 | SHA256 |
|---|---:|---|
| ThreeKingdoms-Godot-v0.5.0-Windows-x64.zip | 86978053 | `269c52bcbb9831ab910ee475577c945ad23dceb299eaa8e7c7d4300973df0acc` |
| ThreeKingdoms-Godot-v0.5.0-Web-preview.zip | 59137219 | `6baa61f3e1a88f40e1ef0e5517b966a587e76a3409c0280bbe0d81846298916a` |

最终独立包确认203项（161静态＋42最终compiledPCK）。两包各56份规则服务文件与当前源码逐字节一致，清单/大小/哈希一致，没有凭据或私人进度。最终PCK在macOS Godot实际加载，验证明确409/同步失败文案、不确定运输禁重发、原编号与原body重连、ACK清回执。

此前解压包用macOS宿主Node执行162项实际canonical HTTP运行，包括建房、满员恢复、援军、掠夺、真实扣款/缴获与返城、原ACK重放及重启不重复交付。最后修改仅为Godot提示与打包说明；最终包110份服务可执行代码与这次运行证据逐字节一致（仅bridge/README文档不同），沿用该162项证据。故**365项独立包审计通过**；不将沿用的162项写成最终新包重新执行。最终报告 `.local/rooms-package-final-audit-050-6di7llp9/final-report.json`，原后台运行报告 `.local/rooms-package-audit-050-ka6aq_k2/runtime-report.json`。

Windows EXE尚未在Windows实际运行，当前CI配置已包含新房间与大厅检查，但未推送触发。0.5.0未公开发布；0.3.1的历史Windows CI不能代替本轮验证。

## 边界与收尾

大厅创建/加入的未确认请求只保存在当前窗口内。关闭或刷新会丢失这份登记重试信息，可能无法取回已创建但未收到密钥的席位；页面/桌面明确提示并提供原请求重试。游戏内命令则继续使用原有按authority＋actor隔离的持久回执。客户端不自动保存登录秘密，成功后玩家自行保存自己的恢复信息。

正式邮箱/Steam账号、公网托管、跨电脑加入、密码找回、真实手机多点触控、Windows人工长局和百人负载均不属于本次已完成范围。Supabase只读发现现有项目用于其他业务，未写入或创建项目，正式后台偏好仍待用户回复。未引入技能、赛季、补给或经济重做。

原仓库clean，HEAD仍为 `c7674df45b9595405e57907524e737e633b0ff63`；旧vendor/legacy、私人bridge/server与dto无差异。0.4.0历史包保留，新源码和包仅在独立仓库本地，未commit/push/release。Graphify按同一code-only/exclude flags本地刷新为726节点、2218边、40社区；不识别.gd/IIFE嵌套依赖仍不完整。没有watcher、hook、外部语义后端或上传。

故事006八项验收均满足，Verdict: COMPLETE。QL-TEST-COVERAGE按qa.level minimal跳过，LP-CODE-REVIEW按solo模式跳过正式director gate；另做的独立后台、客户端、最终PCK与包审计明确记录，不宣称运行了未执行的CCGS专门gate。后续跨电脑部署需要单独游戏后台配置，不自动创建新的开发故事。
