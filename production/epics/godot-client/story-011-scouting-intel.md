# 战前侦察与可见斥候行军

Status: Complete
Last Updated: 2026-10-06
Story Type: Logic / Integration / UI
Layer: Feature
GDD: design/game-brief.md
ADR Governing Implementation: N/A — 接通冻结规则已有 ScoutSystem；桥接只报价和投影，Godot只负责展示与提交合法命令。
Dependencies: story-010-growth-economy.md — Complete

## 授权与范围

用户在讨论游玩吸引力后要求继续更新。本轮补齐现有PvE侦察在新版的操作链：地图选择目标→查看已有情报→按原报价派遣斥候→观察抵达与返程→依情报配兵。原网站、vendor规则、经济、战斗结算和旧进度不改；玩家共享城池侦察继续暂缓。

## 验收

- [x] 侦察报价来自Game.scoutQuote，显示原粮耗、往返耗时、预期精度、损失、有效期与阻塞理由；确认提交dispatchScout[node,count,key]，改数量/城市/目标后旧报价不能发送，断线及pending禁止重复消费。
- [x] 地图详情与出征界面能查看当前目标情报；兵种、区间、精确、公示、失败、过期和旧情报明确区分。未侦察/过期不显示隐藏守军、敌方快照或虚构胜率。
- [x] 斥候加入行军视图，显示出发城、目标、往返阶段、剩余时间、人数及已结算自身损失；所有城市队列可见，不生成原规则不支持的召回命令。
- [x] 返回和情报有效期随真实服务状态更新；同一弹窗更新时保留输入/焦点，切换城市/身份清理不适用报价和旧情报；共享模式不能启用本机侦察。
- [x] 规则与HTTP验证实际派遣、扣费、重复回执、抵达、返程、TTL和多城；原生桌面/390观察，最终网页导出与独立试玩入口可用，保留证据及平台边界。

## 实施与证据

使用CCGS minimal，省略不适用的TR注册与控制清单，本故事不引用ADR；按验收与现有简报实现。Godot专用组件、桥接投影/报价分别实现，root维护主客户端整合。测试只使用隔离存档；原版侦察队列不能取消，本轮不另造取消规则。

证据保存production/qa/evidence/story-011/与production/polish/scouting-intel-report-2026-10-06.md。


## 完成记录

2819项自动检查、373项包检查通过；组件141/主整合70项原生检查与8张隔离截图已复核，最终Web1280/390新档门槛实际观察。实际HTTP及解包规则服务覆盖费用、回执、返程和TTL。窗口适配、普通野地缺失于landmark节点和JSON浮点损失已修复。

本次UI起始条件为prepared，后续侦察使用canonical命令；不作为自然成长时间证明。Windows EXE未实机执行，共享侦察与云联调暂缓。最终包build/scouting-0605/，独立试玩17350；原网页/vendor/旧进度保留。本地Graphify同参数刷新1316节点/3486边/77社区，无监视或上传。
