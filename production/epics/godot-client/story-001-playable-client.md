# Godot 跨平台试玩客户端

Status: DONE — 第一轮独立迁移试玩；非全部原游戏界面迁移。
GDD: design/game-brief.md
ADR Governing Implementation: N/A — 用户已明确选择 Godot＋GDScript 与独立仓库；迁移首轮按以下验收执行。

- [x] 原网页仓库和 Pages 不变；新仓库独立。
- [x] Godot 原生连续地图、滚轮/触屏缩放、地形和行军路线/ETA。
- [x] 原生城池、建筑操作、训练、任务、出征、战斗回合反馈。
- [x] 复用权威规则；存档重开持久化，兼容原 JSON 导入导出。
- [x] 网络重连、错误反馈、幂等与版本冲突处理。
- [x] 导出 Windows 与 Web，实际运行范围和限制记录。
- [x] 新仓库发布源码、试玩包与使用说明；原项目未改。

验证及边界见 docs/QA.zh.md，140 项检查通过，Windows 发布包 headless 实际启动通过。新增私有仓库 YuJieMichael/three-kingdoms-godot，发布 v0.1.0。完整原界面迁移、正式美术、扩州、账号共享世界与 Steamworks 为后续工作。
