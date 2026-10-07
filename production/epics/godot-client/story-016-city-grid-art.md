# 清晰内城地块与写实RTS建筑

Status: Complete
Last Updated: 2026-10-07
Story Type: Visual / UI / Integration
Layer: Presentation
GDD: design/game-brief.md
Requirement: 用户本轮要求清晰的内城格子、选择建筑，以及帝国时代式写实古代战争观感。
ADR Governing Implementation: N/A — minimal，沿用 Godot 2D 客户端与权威规则桥接。
Dependencies: story-014-commanding-city-art.md、story-015-world-map-art.md — Complete

内城恢复清楚可辨的建设地块，建筑贴图采用统一的写实RTS材质、视角和光向。桌面以6列、窄屏以3列排列36个真实site，按原site顺序呈现；官府和保留地仍来自权威布局。空地打开按用途分组的当前建筑目录，先选择建筑并查看该位置的费用、工期和条件，再明确确认建设。只改变表现和操作流程，不改规则、存档或已建建筑的身份。

## 验收

- [x] **AC-1 地块清晰且身份固定。** 36个格子有明确边界、编号和占用状态；桌面6×6、手机3×12按实际site排列。新城官府为site14，site15/20/21为保留地；保留地不提供空地或建筑操作。轮询、换城、重建控件与重复建筑均使用真实site，不按建筑种类重新排位。
- [x] **AC-2 选择与确认建设。** 点击空地后，目录只显示最新`buildOptions`，重复/唯一限制沿用权威DTO；选择建筑只打开详情，不提交命令。确认显示该建筑的真实费用、工期和前置，且只发送`queueBuilding([所选site, id])`。取消、换城、地块已占用、报价变化、资源不足、队列繁忙、pending或断线不会提交旧操作。
- [x] **AC-3 写实建筑实际接入。** 项目保存并使用本轮透明图集、独立建筑贴图和17个视觉区域（当前16种真实内城建筑及装饰城门），地表材质实际接入。统一古代战争材质、视角、尺度与光向，区域与缩放不串图；区域在对应源图范围内，保持原图比例、透明边缘和地面接触。装饰城门不生成可建site。
- [x] **AC-4 真实状态可读。** 只绘制DTO中的实际建筑；空地、保留地和0级施工地不绘成完工建筑。建筑名称、等级、所选地块及升级施工标记可读，贴图不覆盖邻地点击范围或文字。缺失图区时保留可读轮廓和原操作。
- [x] **AC-5 手机与桌面操作。** 390视口及实际内容宽度的地块点击目标至少44px；画面可垂直滚动。触摸释放才选择一次，拖动、取消和多指不会误开详情，触摸合成鼠标不会重复选择；实体鼠标点击仍正确。桌面和390手机实际观察网格、目录、确认、完工和施工状态。
- [x] **AC-6 兼容与证据。** 原城务、升级、城外田庄及其他管理入口保留；vendor权威规则、经济/战斗效果、存档格式、旧进度、原网页与现有Pages不改。root顺序执行针对性GDScript/权威Node回归，保留原生/Web截图与导出资源证据；Windows导出成功、实际Windows运行和物理手机验证分别报告。

## 验证安排

`tests/rts_city_grid_test.gd`验证规则产出的site/重复建筑、响应式行列、保留地、输入及图集边界；`tests/historic_structure_client_test.gd`继续验证旧管理入口，并覆盖选择不发送、确认精确地块和最新报价守卫。已有bridge/realm权威命令测试继续复用，不复制经营规则。实际`Input.parse_input_event`与`ScrollContainer`探针、原生/Web观察和包验证由root顺序运行，避免并行Godot资源压力。

完成证据见 [qa-summary.json](../../qa/evidence/story-016/qa-summary.json)。9组headless共5659项、Node桥接23项、原生1316项通过；最后修复窗口切换后客户端111项再次通过。最终Windows/Web包审计196项，各自导出PCK在macOS加载并接解包规则服务验证76项，各只在独立QA新档确认一次建设；Windows EXE没有在Windows实际运行。最终Web1280×1000与390×844实际检查网格、定位官府、目录→预览→返回→关闭，warning/error为0；HTTP18项通过，玩家预览revision0、无消费，来源与副本存档SHA保持。固定工具栏在城市滚动时保持可见，手机末34–36地块与城门可达。完工、0级地基及升级倒计时来自原生规则准备场景，不修改玩家存档。临时viewport已重置。

内置imagegen的实际prompt、源路径、裁切元数据和SHA摘要已保存。Graphify仅本地code-only刷新与无标签聚类，1327节点/3508边/77社区；GDScript覆盖由源码和运行补齐，不启用watcher、hook、外部后端或上传。原网页保持clean，Pages未部署；不把包导出与物理手机/Windows运行混淆。
