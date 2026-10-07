# 大地图山川、城池层级与操作

Status: Complete
Last Updated: 2026-10-07
Story Type: Visual / UI / Integration
Layer: Presentation / DTO projection
GDD: design/game-brief.md
ADR Governing Implementation: N/A — 沿用Godot地图裁剪与原权威世界。
Dependencies: story-014-commanding-city-art.md — Complete

用户要求大地图建议并实际更新。写实古代战争方向，统一山林和城池贴图，三层缩放，按可见权威tier辨认名城，增加筛选/缩放与行军方向；保留64×64和现有规则。

## 验收

- [x] 山林、城池有统一材质和空间体量；透明图集只加载/切分一次，缺失时保留绘制fallback。
- [x] 可见城市从真实名城定义取得层级，旗色保留关系优先级并识别真实黄巾阵营；未开放任务无贴图/名称泄漏。
- [x] 远景/区域/近景信息分层；筛选、缩放、回城操作在桌面和390宽可用。
- [x] 行军方向与实际ETA可读，驻扎/采集不伪装移动，点击/拖动/缩放锚点与稀疏远景保持。
- [x] 实际原生与Web观察、相关回归和导出；明确WindowsEXE/物理手机边界。

不添加通行地形、补给机制或全国州郡，map_regions仍为试玩分区；不移动地块/玩家、不读取凭据或公开新服务，原GitHub Pages和旧存档保留。最小CCGS故事流程，图谱本地code-only同flags刷新。

## 最终结果

0.6.0-dev.9。六区图集、可见真实城池tier投影、关系旗帜、三层缩放、地图筛选/手机缩放、实际行军方向、服务器时钟和alpha屋顶选择完成。1192 scoped headless checks，原生地图317/连续地形58，Node最终5＋原bridge23独立通过，工具栏59；最终包322检查通过，实际Web1280/390观察且revision0、无mutation/存档变化。WindowsEXE/物理手机未运行；候选性能测量不作为最终FPS证据。

[最终报告](../../polish/world-map-art-report-2026-10-07.md)、[QA摘要](../../qa/evidence/story-015/qa-summary.json)、build/map-art-0609和预览17357记录交付；原网页、vendor规则、旧进度保留。下一轮建议沿此图层组织真实州郡与关隘/交通线，尚未实施全国版图和地形机制。
