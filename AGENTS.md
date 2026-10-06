# 三国城志 Godot 客户端

用户已选择 Godot＋GDScript，目标为 Steam 与网页。原仓库 `../three-kingdoms` 与现有 GitHub Pages 必须保持不变。只在本仓库开发。

客户端代码在 src/；本地规则桥接在 bridge/；vendor/legacy 是来自原作 c7674df 的权威规则快照，来源见 provenance.json。保持规则与存档兼容。不要将随机占位经济替代原规则。

采用 CCGS 的 minimal 工作流，真实验证解析、规则、桌面运行和网页导出；Windows 导出成功与 Windows 实际运行分开报告。正式 Steamworks 与公网多人服务需后续配置。

Graphify 仅本地 code-only，排除 .claude/** 与 docs/engine-reference/**。0.9.76 未识别 GDScript 的 .gd，IIFE 引擎函数图谱也不完整；图查询后检查 Godot 源码，不把缺失当成没有依赖。禁止自动watcher、hook或上传。

用户已选择 [game-development/pc-games](/Users/lihuazeng/.codex/skills/game-development/pc-games/SKILL.md) 工作流，入口为 [game-development](/Users/lihuazeng/.codex/skills/game-development/SKILL.md)。桌面开发按动作抽象输入、先测量再优化，并区分导出与实际运行验证；沿用现有 Godot＋GDScript 和 canonical 规则桥接，避免复制经济或战斗结算。安装来源与后续顺序见 [PC 工作流说明](docs/PC-GAMES.zh.md)。
