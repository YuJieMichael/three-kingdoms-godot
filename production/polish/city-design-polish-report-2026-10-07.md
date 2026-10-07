# 城池空间、成长外观与建设决策更新

状态：Complete。日期：2026-10-07。版本：0.6.0-dev.11。对应 [story-017](../epics/godot-client/story-017-city-design-polish.md)。六项源码、原生、最终Web、两包编译资源与隔离新档实际建造验收通过。

本轮落实用户选择的六项设计建议，让36格城池更像有街巷、城墙和成长阶段的古代城镇，并让新建、升级和出征准备所需的信息更清楚。继续采用 Godot 客户端与 canonical 规则桥接，真实地块身份、重复建筑、保存格式、经济和战斗规则保持兼容。开发范围是独立 Godot 仓库；原网页仓库与 GitHub Pages 保留，本轮不部署原网页。异步 PvP 策略大改、名将技能、正式云联调沿用暂缓决定。

## 六项改动

| 范围 | 当前实现与验收重点 |
| --- | --- |
| 1. 街巷与地表 | 36个真实地块按编号排列，电脑6列、手机3列；统一格子保留低对比地界，宽主街连接南门，窄支路与夯土纹理组成连续地表。视觉重排不改变 site、建筑或费用。 |
| 2. 城池环境 | 城墙绘顶面和厚度，南门与主街对齐；三处官署留地绘院落和树。环境装饰不生成建设地块，图缺失时保留可读的庭院、树形和墙体回退。 |
| 3. 成长外观 | 官府、军营在已完成等级1–3、4–7、8–10使用低、中、高三阶图。0级只有地基，升级中使用当前完成等级；可用低阶或基础图承担缺图回退。建筑保持源比例并让开地块编号、等级和队列标记。 |
| 4. 同窗建设目录 | 民生、军备、科技、全部分类及“当前可建”筛选在同一窗口运行；目录、详情、返回保留分类、筛选和目录位置。选择只展示报价，确认由 main 再核对当前城、准确空地、最新费用/工期/条件、资源、队列、连接和待处理命令。固定费用、工期和确认位于详情滚动区外；手机窗口保持350×556，目录返回真实滚动100→100，长对照滚动475时费用与确认仍完整可见。 |
| 5. 手机城池空间 | 窄屏资源用单行短名和数量呈现，可点开详情；当前目标用“展开/收起”按钮展开完整描述和奖励，三枚操作按钮保持44px高；前往、领取、成长入口保留。城池页空闲军情折叠，有训练、防御、行军、战报、战斗或重要警告时保留提醒；施工队列有独立入口，可回到准确城内/城外地块；空队列三行说明避免撑宽窄屏窗口。 |
| 6. 民房与军营收益对照 | 新建报价绑定所选空地；逐座升级列实际 site、当前/目标级、费用、工期、完成后容量增量与总上限，并显示施工、满级、满城、缺前置、缺资源及队列不可用原因。民房说明人口上限增加后仍需人口增长；军营说明增加的是可排队训练订单数，订单依次开始。校场的单队人数能力继续由原规则处理。 |

## 素材、规则与数据边界

保留 story-016 的16类实际内城建筑及门楼基础素材。本轮新增 `city_rts_progression_v1.png` 的6个等级区域、`city_rts_environment_v1.png` 的4个环境区域，并以 `city_ground_rts_v2.png` 提供地表。区域、源尺寸与 SHA 见 [city-rts-art-atlas.json](../../data/city-rts-art-atlas.json)；生成 prompt 见 [RTS_POLISH_GENERATION_PROMPTS.json](../../assets/environment/city/RTS_POLISH_GENERATION_PROMPTS.json)，原始生成源审计见 [asset-source-audit.json](../qa/evidence/story-017/asset-source-audit.json)。两张新增图集均为1536×1024，透明通道保留；区域互不交叠，alpha>16轮廓距裁切边至少2px。地表为1254×1254不透明纹理。素材像素、源比例和透明通道未通过后处理重写。

收益对照由 `bridge/building-comparison.mjs` 接入 `gameView`。当前人口上限和训练订单容量直接调用 canonical `maxPop()`、`trainingLimit()`；增量读取原 `buildRecord()` 的贡献，费用、工期、条件、支付能力和队列上限使用原函数。canonical 训练容量没有额外基础值、夹取或加速奖励；各等级的表项增量已与真实 `queueBuilding()` 到 `tick()` 完工结果对照。高频读取不为每个候选创建规则 runtime，不 tick、save 或提交命令。

对照仅投影本人当前城；shared 模式复用本人 `gameView`，公开敌方节点不携带此字段。0级施工不计已建座数或升级候选，已有升级队列和最高级候选明确不可用。返回的费用与队列是独立副本。新建候选以真实最小空 site 为默认，UI 展示和确认仍绑定用户实际选择的空 site；原规则中相同类型/等级的价格与容量不因位置改变。

## 已有证据与最终核对

| 检查 | 已保存结果 | 实际边界 |
| --- | --- | --- |
| 新增 Node 收益测试 | 8/8通过，覆盖全等级真实建设/升级完工、重复建筑、施工与各不可用状态、跨自有城、shared本人范围、公开敌方字段隔离、无 live state 副作用及高频读取。 | 使用隔离 canonical fixture 与 snapshot；没有修改真实玩家进度。 |
| Node 兼容回归 | 桥接23项与战报预算7项联合30/30通过。 | 执行命令、时长和结果见 [agent-test-results.json](../qa/evidence/story-017/agent-test-results.json)。原始 stdout 未保留，文件明确为代理执行摘要；为补证据没有重复跑测试。 |
| 素材与城景 | 原素材尺寸/SHA匹配审计；三张最终 native 城图独立视觉复核未见阻断遮挡、串图、暗底块或比例问题。 | 图中可见36地块、庭院、0级地基、完成等级和施工标记；不是点击命令或触摸行为证明。 |
| Godot、输入与 UI 回归 | 11组5973项通过，0失败、无错警。面板36、客户端236为最后窄屏修复后重跑结果；其余城景、输入与旧操作分组保持通过。 | 见 [scoped-gd-results.json](../qa/evidence/story-017/scoped-gd-results.json)，复跑和旧截图不累加。 |
| 原生城景与建设弹窗 | 城景1324项、最终面板37项通过，合计1361项；建设截图已替换为最终源。 | [native-final-results.json](../qa/evidence/story-017/native-final-results.json)与[native-panel-visual-review.json](../qa/evidence/story-017/native-panel-visual-review.json)。真实390×844 Window中报价、确认、返回与关闭可见；完整城景图仍不替代实际viewport操作。 |
| 最终 Web、包与存档 | Web桌面1280×1000、手机390×844通过，error/warning均0；HTTP20、包审计205、两份编译PCK各93项通过。 | [浏览器记录](../qa/evidence/story-017/web-browser-review.json)、[HTTP](../qa/evidence/story-017/web-http-results.json)、[包审计](../qa/evidence/story-017/package-report.json)、[编译资源](../qa/evidence/story-017/compiled-results.json)；各解包服务的一次实际建设使用独立一次性新档，玩家预览不提交指令。 |

已保存的 native 图是 macOS Godot 的真实场景渲染、canonical 准备场景，未加载玩家存档。桌面图为900×1287，手机图为390×2064完整内容截取：

- [已建设桌面城景](../qa/evidence/story-017/rts-city-grid-developed-desktop.png)
- [新档手机城景](../qa/evidence/story-017/rts-city-grid-fresh-phone.png)
- [施工与升级手机城景](../qa/evidence/story-017/rts-city-grid-mixed-phone.png)

[visual-review.json](../qa/evidence/story-017/visual-review.json) 保存各图尺寸/SHA与观察边界。手机完整城景图显示地块01的0级民房地基和59秒倒计时、地块18的3级民房升级和29秒倒计时；保留庭院位于显示编号16、21、22，官府位于15，末排34–36和南门可见。这些手机尺寸不是实体手机测试，也不能证明390×844实际 viewport 的固定 HUD、拖动滚动或官府定位。最终Web在390×844验证末排/南门滚动、固定工具栏、官府定位、资源详情、中文目标展开、同窗目录返回、固定费用和确认；来源及最终受影响功能复核见浏览器记录。

视觉余项为北/南墙重复段接缝仍明显，侧墙细节低于建筑，整齐空城和笔直街巷仍有规划图感。独立审核认为这些不阻断本轮清晰格子与写实建筑目标；后续可继续打磨。

高频测量当次1000次收益投影共709.39ms，约0.709ms/次，显式GC后保留堆增加48,144B；20次完整 `gameView` 共5513.28ms，约275.664ms/次，保留堆增加522,744B。后者包括既有管理/报价工作，不能当作新增对照计算成本；这是一台 macOS 主机在其他检查同时运行时的单次观察，保留堆也不是峰值内存。

## 交付与验收

本机试玩：[打开新版城池](http://127.0.0.1:17359/)。最终交付目录`build/city-polish-0611-final/`，浏览器tab81已保留、viewport已恢复。Windows完整解压后运行`ThreeKingdoms.exe`；网页包运行`StartWeb.cmd`或`start-web.sh`，按包内说明连接本地规则服务。

| 包 | 字节数 | SHA-256 |
| --- | ---: | --- |
| Windows-x64 | 104317922 | `237247d42e7ea9253a779589ea6b0a55394c21892ea19fd47e8942a51a275e15` |
| Web-preview | 76475307 | `ea1ebd3d3b829ac9ea35f883607fd1231507c0b720cba7b008c000626896ff8c` |

[manifest](../qa/evidence/story-017/build-manifest.json)、[SHA256SUMS](../qa/evidence/story-017/SHA256SUMS.txt)与[QA聚合](../qa/evidence/story-017/qa-summary.json)保存最终范围。5973项headless、38项Node、1361项native、205项包审计、93×2编译资源和20项HTTP分别报告，不累加旧版、诊断或重复执行。两个编译资源测试运行在macOS Godot，各连接自身解包的规则服务，在一次性新档确认第36格民房，获得revision1回执、0级地基和真实计时；不代表Windows EXE已运行。

原进度与预览副本最终摘要均为`bf0d7befeaae395b50c74caaf85764a6b2f1e1469fc547f1bde8155cd7e83725`，见[save-integrity](../qa/evidence/story-017/save-integrity.json)。网页浏览没有提交消费/领取指令，预览revision0；原规则仍会随时间推进即时资源显示，不能把持久化摘要不变解释为暂停游戏时间。原仓库clean、HEAD仍为`c7674df45b9595405e57907524e737e633b0ff63`，vendor无diff；没有提交、推送或部署原网页。

建设窗口曾被零宽自动换行的瞬时minimum撑至1205高；先绑定报价Label真实宽度后固定为350×556，目录位置恢复100→100，长对照可真实滚动。实际Web还发现目标展开误用0可见行、箭头缺字、按钮随长描述拉高、空队列说明撑宽，均修复并补实际渲染/Window边界断言。最终截图已替换，旧阶段记录保留但不当作最终通过。

编译探针早期并发运行一次Web启动80秒超时，后改串行并给启动150秒上限；最终两包均约12秒完成。另一次Web探针在93项通过后的即时退出报告4个对象；verbose确定为两条AudioStreamWAV及其Playback。探针经已有SoundManager停止循环音乐、回执/点击音效并等待250ms后，两包退出均无错警；只调整测试收尾，游戏源与最终包摘要不改。见[退出诊断](../qa/evidence/story-017/compiled-exit-diagnostic.json)。

最终本地Graphify为1339节点、3532边、78社区，沿用code-only/exclude和无标签聚类；GDScript、SQL解析及嵌套IIFE覆盖限制保留。新增收益投影经局部查询及源码/实际完工核对，未启用watcher、hook、外部语义后端或上传。

正式 Windows EXE 硬件运行、物理手机、正式账号/公网服务及 Steamworks 不在当前已验证范围。源仓库图查询使用本地 Graphify；GDScript 不在其覆盖范围内，关系判断仍核对当前源码，不启用 watcher、hook 或上传图谱。
