# 地图优先的战争界面

Status: Complete
Last Updated: 2026-10-07
Story Type: UI / Integration / Visual
Layer: Presentation
GDD: design/game-brief.md
ADR Governing Implementation: N/A — 沿用Godot容器、原报价命令与界面DTO，界面组织改版。
Dependencies: story-011-scouting-intel.md — Complete

## 授权与布局

用户确认此前建议的1/2/3/4/5全部实施：地图主体、紧凑资源与手机底部导航、同窗侦察配兵报价确认、军队状态常驻、写实古代战争氛围。只改独立Godot版；vendor、原网页、存档格式和经济不改。

桌面默认收起任务栏，选中目标才显示详情；资源只显示数量，点击查看容量/产量。手机保留一行资源、简短当前目标和底部五页导航。统一出征窗口按情报/配兵/报价/确认组织，侦察切页仍在同一窗口，确认留在滚动区外。军队栏按真实队列/行军/驻扎/战报显示，倒计时到0提示待结算。

## 验收

- [x] 桌面地图默认获得主要空间，任务可展开收起；详情只对当前目标显示，关闭后复用地图而不重置镜头。
- [x] 390资源一行，点击能查看实际数量、容量、产量和超仓说明；底部导航、任务、军队入口可键盘/触控访问，无横向溢出。
- [x] 同一出征窗口查看军情、选择将领兵力和占领返回选项、取得原报价并确认；侦察切换不叠窗，确认始终可见。输入/城池/目标/连接/pending变化正确撤销旧报价，精确提交原命令且不能重复扣费。
- [x] 常驻军队栏显示真实本城训练与全域可见行军/驻扎/战报；时间和回执更新保持焦点，身份切换清旧数据，不生成不存在的未读数或自动结算。
- [x] 深灰、铜金、米白统一层次，地图地形/城池旗帜改善；保持隐藏据点、敌我颜色、地图坐标、筛选、平移缩放、路线和现有稀疏索引性能语义。
- [x] 源码解析、相应规则和界面回归通过；最终桌面/390原生与网页实际观察、Windows/Web导出及包检查有证据。Windows导出与实机运行分开报告。

## 流程与证据

CCGS已实际解析collaborative/minimal/coarse/qa minimal，testing.strict unset，system overrides none。本故事ADR N/A；省略TR注册和control manifest。root主布局/整合，三个子代理分别视觉、出征、军队栏并行；验证新窗口与身份/报价边界，再按minimal关闭故事。

证据production/qa/evidence/story-012/；报告production/polish/war-interface-report-2026-10-07.md。测试与预览使用隔离数据，不覆盖玩家进度。

## 最终结果

3166项自动检查通过（Node183、SceneTree2964、HTML19），32个GDScript入口无SCRIPT ERROR/ERROR；主界面原生101项通过。最后一个旧测试因出征窗口句柄/按钮名迁移而中断，更新测试至统一窗口并增加失败退出后125项完整通过，没有改动生产源码。最终Windows/Web两包480项检查通过，最终Web1280/390已实际观察，console warning/error为空，新档revision0。Windows EXE未实机运行。

行军列表按最新快照更新或增删记录；驻扎返程切换保持正确筛选，按钮读取最新命令。私人旧规则召回先选择对应部队，再核验服务器回执中的出发城/节点/阶段，拒绝错城回执。完整验收、包摘要及private API原始城市数据的范围说明见报告与qa-summary.json。
