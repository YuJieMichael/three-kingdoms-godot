# Godot 跨平台试玩客户端

Status: IN PROGRESS
GDD: design/game-brief.md
ADR Governing Implementation: N/A — 用户已明确选择 Godot＋GDScript 与独立仓库；迁移首轮按以下验收执行。

- [ ] 原网页仓库和 Pages 不变；新仓库独立。
- [ ] Godot 原生连续地图、滚轮/触屏缩放、地形和行军路线/ETA。
- [ ] 原生城池、建筑操作、训练、任务、出征、战斗回合反馈。
- [ ] 复用权威规则；存档重开持久化，兼容原 JSON 导入导出。
- [ ] 网络重连、错误反馈、幂等与版本冲突处理。
- [ ] 导出 Windows 与 Web，实际运行范围和限制记录。
- [ ] 新仓库发布源码、试玩包与使用说明；原项目未改。
