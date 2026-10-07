# 城内建筑图集 v1

生成方式：Codex 内置 `imagegen`，2026-10-07。项目内资产为 `city_buildings_commanding_v1.png`；原始输出保留，项目副本未经像素修改。透明alpha实际核验；运行时以 `data/city-art-atlas.json` 区域裁取与等比例contain缩放，无Python图片编辑。

此图是战争游戏建筑表现，不宣称精确复原具体年代/城池。构图强调官署台基、门楼、院落与重檐；图中装饰仅美术，无新增功能。

最终生成提示：

```text
Use case: historical-scene.
Asset type: ONE coordinated transparent sprite atlas for the existing 2D Three Kingdoms strategy game Shanhece, not a UI mockup or illustration background.
Primary request: make ancient Chinese city buildings commanding and imposing through stronger architectural mass and realistic material texture.
Composition: wide landscape canvas 1536x1024, EXACTLY 3 equal columns by 2 equal rows, six isolated complete compound sprites. Each sprite centered entirely within its own cell with at least 36px of transparent padding on all sides. No overlap between cells. Clear alpha transparency in the gutters. No grid lines, no titles, no labels, no letters, no numbers, no watermark.
Row 1 left: monumental Han-inspired GOVERNMENT COURTYARD, dominant layered charcoal tiled hall on a high pale stone foundation, broad central stair, deep timber pillars and crimson beams, symmetrical flanking smaller halls and an open paved forecourt, restrained rather than imperial gold decoration.
Row 1 middle: commanding WALLED CITY GATEHOUSE, heavy weathered rammed earth lower gate structure, massive dark open central gateway, layered charcoal roof tower, timber gallery, two restrained crimson military pennants. Short wall stubs only, complete outer silhouette.
Row 1 right: MILITARY BARRACKS compound with broad tiled barrack halls, heavy timber gate, a few sand-colored command tents, weapon rack, two dark crimson banners.
Row 2 left: WAREHOUSE compound, two round raised grain silos with thatch caps and one long large timber granary, stone supports and bundled sacks, robust logistics silhouette.
Row 2 middle: ENCLOSED MARKET compound, heavy timber market gateway/watch pavilion and grouped sand-colored merchant awnings, modest goods crates, visibly commercial.
Row 2 right: RESIDENTIAL compound, three modest weathered tile-roof timber dwellings around a small earthy courtyard, lower in status and mass than the official hall.
Style/medium: polished hand-painted realistic 2D strategy-game environment sprites, architectural miniature material detail, crisp readable large shapes, rich tile rows, rammed-earth layers, substantial timber frames; realistic war atmosphere without ink painting or cartoon shapes.
Camera: uniform elevated near-frontal orthographic view, roof surfaces and front facades visible, very little side perspective, building axes vertical/horizontal so they sit on the game's rectilinear town plan. Front of EVERY courtyard faces straight down toward bottom of canvas. One consistent scale language, lighting from upper left, cast shadows kept within each cell.
Palette: slate blue charcoal tiles, warm ochre rammed earth, pale warm-gray stone, dark brown timber, restrained muted crimson; sufficient contrast against olive earthy ground. Do not paint any landscape outside each building's immediate foundation. Do not include modern elements, ornate late imperial palace excess, fantasy towers or people.
Background: true alpha transparent, preserve clean antialiased edges and subtle attached contact shadows.
```
