# 界面与操作反馈优化

Status: Complete
Last Updated: 2026-10-06
Story Type: UI / Visual/Feel
GDD: design/game-brief.md
ADR Governing Implementation: N/A — 沿用现有Godot容器、canonical快照和命令接口，只优化呈现。
Dependencies: story-008-playable-completion.md — Complete

## 目标

使用game-ui-ux、game-ui-design和game-feel完成一轮可试玩优化。收敛重复入口，让手机始终看到当前目标，分清菜单与主要动作，并让每回合移动、攻击和伤亡反馈更清楚。

## 验收

- [x] 顶栏精简；五页导航有同步的文字与选中态；现有功能通过事务或菜单仍可到达。
- [x] 资源紧凑且超仓提示明确；390窄屏持续显示当前目标，断线、未确认操作及身份切换正确更新。
- [x] 事务按成长、经营、军务、物资分组；目标实时刷新不重建窗口，键盘默认焦点安全且关闭后恢复。
- [x] 统一面板、按钮、输入和焦点视觉；确认提示短暂反馈，不阻塞输入。
- [x] 战斗分阶段显示移动、攻击、受击和伤亡；轮询不重播，始终恢复canonical最终位置。
- [x] 菜单提供持久化减少动态效果选项，保存失败保留旧值；不会暂停行军、建设或规则时间。
- [x] 实际桌面与390宽度运行观察、解析与相关回归通过，保留截图和真实验证边界。

## 范围

只修改独立Godot客户端的UI与表现层。原网页仓库、冻结规则、存档格式和经济数值不变。本轮不接公网、Supabase、Steamworks或重做技能。

## 证据

production/polish/ui-feedback-report-2026-10-06.md；production/qa/evidence/story-009/。
