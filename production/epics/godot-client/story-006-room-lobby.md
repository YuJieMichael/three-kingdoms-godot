# 1–8人房间与城主恢复

Status: Complete
Last Updated: 2026-10-06
Story Type: Integration / UI
GDD: design/game-brief.md
ADR Governing Implementation: N/A — 保留canonical规则，新增独立本机房间服务与大厅，尚不部署公网。
Dependencies: production/epics/godot-client/story-005-shared-pvp.md — Complete

## 目标

用户要求继续下一轮开发。将四个固定虚构账号之外的房间、邀请加入与自己的城主恢复做成可运行流程。房间最多8人，服务器创建独立城池、稳定身份和权威进度。当前使用明确标注的备战演练开局；正式外网账号与托管后端另行配置，不修改原网页或既有规则。

## 验收

- [x] 创建1–8人房间、凭邀请码申请空席位、凭自己的恢复密钥返回原城池；昵称和邀请码不能接管已有玩家。
- [x] 每房间使用服务器生成身份、独立canonical世界、唯一稳定authority；不同房间的状态、行军、资源和回执互不读取。
- [x] 创建/加入原请求编号可安全重试；并发人数上限、成员身份与游戏新档在同一原子事务提交，重启与写盘失败保留正确结果。
- [x] 原攻防、援军、服务器自动结算、返程和命令回执通过房间服务运行；四账号演练和私人试玩保持兼容，vendor快照不变。
- [x] 网页大厅与Godot桌面/窄屏大厅可创建、加入、恢复；新会话经健康鉴权后交接，失败不残留其他城主的数据。
- [x] 邀请/恢复/进入游戏的凭据不会进入日志、查询参数或普通命令日志；只显示本人的恢复密钥，不自动保存客户端凭据。
- [x] 完成HTTP/SceneTree与实际Web/原生房间验证，保存截图、检查计数及局限。
- [x] 提供独立房间启动入口、操作说明和Windows/Web本地包；公网、Supabase、Windows实际运行与正式Steam集成分别报告。

## 范围

CCGS minimal dev-story → story-done。本轮不引入新经济、补给、赛季或技能。新房间的备战预设每位成员一致，按席位交替分配两组演练联盟；使用原作自动战斗。邀请码只给予加入空席位的权限；自己的密钥才可恢复已有城主。创建/加入未确认时保留内存中的原请求，不自动将秘密写到客户端存储；成功后提示自行保存恢复密钥。

服务只绑定loopback，17343独立私有目录，不复用17339私人进度或17342四账号存档。Supabase只读取已连接项目列表，当前项目属于另一业务，未写入；用户对独立游戏后台的部署偏好等待回复。正式账号不是本地席位密钥，当前不宣称朋友已能跨电脑加入。

## 验证记录

Run result: OBSERVED / PASS — 1187项核心检查、365项独立包审计、真实macOS/Web房间与最终导出观察通过。见 production/polish/room-lobby-report-2026-10-06.md。


## Completion Notes

**Completed:** 2026-10-06
**Criteria:** 8/8通过，无延期验收。
**Deviations:** 无；公网账号、Supabase、Windows实际运行和Steamworks均为范围外待配置项。大厅登记仅同窗口内存重试的边界明确提示。
**Test Evidence:** tests/room-bridge.test.cjs、tests/lobby_api_test.gd、tests/lobby_ui_test.gd及报告内真实截图。
**Code Review:** 独立后台/客户端审查完成，损坏存档P1及实际GUI的409提示P2已修复复核；CCGS solo正式LP gate跳过，未伪造director批准。
**Artifacts:** 最终0.5.0 Windows/Web本地包、build/build-manifest.json、docs/ROOMS.zh.md。未公开部署或发布。
