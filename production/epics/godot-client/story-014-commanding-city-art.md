# 城内建筑体量与材质贴图

Status: Complete
Last Updated: 2026-10-07
Story Type: Visual / UI / Integration
Layer: Presentation
GDD: design/game-brief.md
ADR Governing Implementation: N/A — 沿用 Godot 2D 绘制，贴图只负责表现。
Dependencies: story-013-historic-city-structure.md — Complete

用户要求贴图和城内建筑更威武。采用统一的写实战争游戏材质与光向，强化官署重檐、台基、门庭和城门楼的体量；民居、军营、市场与仓储保持用途差异。新贴图存入本仓库，实际接入城池场景，原城门主街/四坊关系、真实site身份、等级与施工/触控语义保留。

## 验收

- [x] 官署、城门和已有建筑有更清楚的体量、材质与光影，使用统一贴图风格并与地表结合。
- [x] 贴图已在项目内保存并实际绘制；区域与缩放不串图，不把未建、保留地或0级施工地绘成完工建筑。
- [x] 道路、地块身份、等级标签和施工状态清楚；不移动玩家位置，不增加经济或战斗效果。
- [x] 桌面和390窄屏实际观察，点击/触摸滚动/重复建筑正确；导出Web与Windows包，明确实际运行边界。

最小CCGS故事流程；原网页、vendor权威规则和存档格式不改。生成资产采用内置imagegen，记录实际prompt、文件、区域和校验摘要；图谱仅本地code-only，GDScript覆盖由源码与运行补齐。

## 最终结果

0.6.0-dev.8完成两套透明图集，18个缓存区域实际覆盖16类权威建筑与门楼，备用募兵所不增加地块/建设选项。桌面1160/窄屏900高，等比、底部锚定、真实site、施工/空地、标签和触控滚动保留。浏览器发现既有窄屏费用横向溢出，局部换行后真实390窗口/Label边界与原报价全部核对。

相关12个GDScript入口聚合5380项、最终macOS主整合88项、独立触控48项通过；最终Windows/Web归档183、两compiled PCK各51、HTTP15，共300项通过。实际Web1280×1000/390×844观察完成，未消费，revision0和save摘要不变；最终重载后warning/error0，历史启动锁/切包瞬断如实记录。Windows EXE和物理手机未运行。生成用内置image_gen，两PNG像素副本未改，完整prompt和来源摘要保存。

[最终报告](../../polish/commanding-city-art-report-2026-10-07.md)、[QA聚合](../../qa/evidence/story-014/qa-summary.json)、[最终包核对](../../qa/evidence/story-014/package-audit-summary.json)及同目录build-manifest.json记录边界。最终包build/commanding-art-0608-final，预览17356服务与tab76保留；原网页、旧进度和17355保留，本地交付，不提交、推送或公开Release。
