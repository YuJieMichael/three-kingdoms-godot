# 本机完整玩法收尾

Status: Complete
Last Updated: 2026-10-06
Story Type: Integration / UI
GDD: design/game-brief.md
ADR Governing Implementation: N/A — 继续现有canonical规则、命令回执与Godot界面组合，不改变经济或战斗公式。
Dependencies: story-002-city-management.md、story-006-room-lobby.md — Complete

## 目标

用户要求在Supabase联调之前先完成游戏。本轮先按完整本机试玩版收尾，原仓库和Pages不变，真实数据库联调暂缓。保留既有章节、官爵珠宝门槛、画像抓将、资源超仓与兵种规则；技能与策略重做继续暂缓。公网托管和Steamworks不是本轮完成前置。

## 验收

- [x] 完整任务册、黄巾史诗捐献、每日任务及奖励、官爵晋升与俸禄有可操作入口，费用与条件来自原规则。
- [x] 野将打听、购买画像、地图定位与出征、俘将招降可走通；将领详情支持现有成长点、训练和装备操作，不重做技能。
- [x] 伤兵治疗、俘虏一键招降、城防建造与已有来袭演练可以操作，失败原因与费用明确。
- [x] 多城切换、建城门槛、运输与调遣入口齐全，操作范围保持现有sourceCity语义。
- [x] 城外样板及现有自动建设/研究入口可用，宝物支持目标选择、礼包开箱和商城购买，使用规则不在客户端重写。
- [x] 任务与新手目标可以引导至对应功能，章节据点仍按当前阶段显示；县城/章节门槛不再因缺少UI阻断。
- [x] 桌面与窄屏可读，未连接/待确认/失败/成功状态有反馈，轮询不重复执行命令或覆盖未提交输入。
- [x] 真实本机规则集成、Godot运行及Web导出验证完成，私人/共享进度和原仓库不被测试覆盖。

## 实现分工

- `bridge/progression-view.mjs` 与 `src/progression_dialog.gd`：主线、日常、史诗和官爵。
- `bridge/hero-view.mjs` 与 `src/hero_dialog.gd`：野将线索、画像、俘将及成长装备。
- `bridge/war-view.mjs` 与 `src/war_management_dialog.gd`：战后补员、城防、现有城池管理命令。
- 根代理集成 `bridge/dto.mjs`、本机/共享投影、`src/main.gd`，并补多城、资源样板与宝物目标选择。

新投影由现有runtime系统生成，报价只读；真实操作仍经executeGame白名单及现有CAS/回执。共享房间与本机PVE能力有明确区分，不能直接放开共享模式被禁用的私人NPC战斗或泄露其他玩家情报。

## 验证

针对新增命令入口进行有意义的集成检查、重复回执与持久化验证；对界面执行费用/禁用/待确认/轮询保留输入和窄屏布局检查。保留实际桌面/Web截图与运行日志，报告Windows导出和实际执行的差别。完整游戏上线不由该故事冒充。

## Completion Notes

Run result: OBSERVED — 最终Web桌面与390宽度实际观察，证据在 `production/qa/evidence/story-008/`。1814项自动检查与192项最终包检查通过；验收报告见 `production/polish/playable-completion-report-2026-10-06.md`。两份最终编译PCK加载实际规则状态及4096地图成功，Windows EXE尚未执行。

| 验收 | 证据 | 状态 |
|---|---|---|
| AC1任务、每日、史诗、官爵 | progression-management.test.cjs、progression_management_test.gd，02–07/31截图 | COVERED |
| AC2野将、画像、招降、培养装备 | hero-management.test.cjs、hero_management_test.gd，10–13/32–33截图 | COVERED |
| AC3伤兵、俘虏、城防及来袭 | war-management.test.cjs、war_management_test.gd，14–19/36截图 | COVERED |
| AC4多城、建城及运输 | realm-management.test.cjs、realm_management_test.gd，20–21/34截图 | COVERED |
| AC5样板、自动化、宝物商城 | realm/inventory管理测试，22–26/35/37–38截图 | COVERED |
| AC6功能导航、章节门槛 | fresh/late规则链、playable_ui_test.gd，30–31/39截图 | COVERED |
| AC7布局、反馈与输入保存 | 五类面板255检查、集成123检查、桌面/390截图 | COVERED |
| AC8真实规则/运行/Web/进度隔离 | 全部自动检查、独立包HTTP、编译PCK、原仓库/快照检查 | COVERED |

Review mode: solo/minimal；分工代理实际复核自身模块，根代理整合、运行全部回归、检查截图和最终包。不宣称额外独立审查或人工Windows试玩。没有GDD/ADR规则偏离；本轮补接口和界面，原经济/兵种/战斗规则未改。

未验证边界：未加速首战链累计800分钟模拟时间，未证明实际等待节奏；后期使用合法高阶fixture。自然成长平衡、正式美术、各州、技能/计谋、联盟扩展、真实联网及Steam发布属于后续工作。故事007按用户要求暂停联调，仍In Progress。

同源码cb2a4ef的Windows/Linux CI37540027451已completed/success；仅源码客户端smoke，导出Windows EXE步骤跳过。随后只更新验收文档。
