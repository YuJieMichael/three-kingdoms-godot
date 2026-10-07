# 城池空间、成长外观与建设决策

Status: Complete
Last Updated: 2026-10-07
Story Type: Visual / UI / Logic / Integration
Layer: Presentation and read-only authoritative projection
GDD: design/game-brief.md
Requirement: 用户选择设计评审建议1–6全部实施。
ADR Governing Implementation: N/A — minimal，保留 Godot 客户端与 canonical 规则服务。
Dependencies: story-016-city-grid-art.md — Complete

36格自选建设继续沿用真实site。城景通过低对比地界、宽主街与窄支路、夯土材质、有厚度的城墙与官署庭院组成更完整空间。官府和军营按已完成等级1–3/4–7/8–10呈现三阶外观；0级和升级中不提前显示未完成结果。建造目录分类、筛选与详情在同一个窗口切换并保留浏览位置，确认仍核对当前城池/地块/报价。窄屏城池页收紧资源与目标，无活动军情折叠，施工和重要军情有入口。民房和军营只读对照新建与现有各座升级的真实费用、工期、容量增量。

## 验收

- [x] **AC-1 街巷结构。** 36地块6/3列与canonical编号、官府/保留地身份不变，地界清楚但低对比，主街宽于支路，夯土纹理不抢建筑；手机目标≥44px且末排可滚动抵达。
- [x] **AC-2 城池环境。** 城墙顶面/厚度可见并与南门连贯，官署留地绘真实庭院/树，环境装饰不生成可交互site，不覆盖地块标签与命中区域。素材缺失仍有可读回退。
- [x] **AC-3 成长外观。** 官府和军营各三种原创建筑贴图，在已完成等级1/4/8边界切换；0级只有地基，升级队列保持当前级，缺tier回退base。源alpha/比例、裁切区域、实例site及倒计时保持。
- [x] **AC-4 同窗建设。** 用途标签与当前可建筛选可访问全部合法选项；目录→详情→返回保持同一Window、原分类/筛选/滚动。费用和确认固定可见，选择不提交，确认原source/site/quote/condition/affordability/queue/connection/pending守卫保留，取消无扣款。
- [x] **AC-5 手机空间。** 城池窄屏资源压成一行，当前目标可展开且前往/成长仍可用；无活动军情折叠，有活动/重要提醒保留可达入口。施工入口清楚；其它页面导航/军情和键盘操作兼容。
- [x] **AC-6 建设收益对照。** 民房/军营新建与升级候选来自本人当前城canonical记录和getter，列费用、工期、完成后容量增量/上限、实际site/条件；施工中/满级/满城/缺前置/资源/队列正确说明。军营只增加可排队订单容量，校场管单队人数，不宣称并行或加速。读取不能改live state、保存格式、回执或他人情报。
- [x] **AC-7 兼容和运行。** 验证实际建造完成前后容量、跨自有城、shared本人投影、旧操作与触摸；依次进行针对性Node/GD、原生与最终Web观察、独立新档确认建设及两包审计。玩家进度保持，原网页/Pages/vendor规则不改；Windows导出与EXE硬件执行、窄屏与物理手机分别报告。

## 证据计划

Node实际queueBuilding→tick对照全部等级，避免新建一套容量规则。Godot覆盖tier边界/施工、主街与环境裁切、同窗/返回滚动与报价守卫、空闲与活动HUD。准备城景截图与玩家进度截图分开；所有可见更改实际观察。内置image_gen生成源与完整prompt保存在assets/environment/city/RTS_POLISH_GENERATION_PROMPTS.json；最终源像素不改。Graphify本地同code-only/exclude标志刷新，不启用watcher/hook/backend或上传。

## 最终验收

5973项GD、38项Node、1361项native通过，最终Web桌面/390实际观察、0warning/error；205项包审计、两PCK各93及HTTP20通过。完整证据与修复过程见production/polish/city-design-polish-report-2026-10-07.md及production/qa/evidence/story-017/qa-summary.json。原进度/副本摘要不变，原网页clean/vendor无diff；Windows EXE、实体手机和正式公网平台边界明确。
