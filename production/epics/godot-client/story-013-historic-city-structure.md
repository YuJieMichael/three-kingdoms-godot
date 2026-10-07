# 城池与城外的历史空间结构

Status: Complete
Last Updated: 2026-10-07
Story Type: UI / Integration / Visual
Layer: Presentation
GDD: design/game-brief.md
ADR Governing Implementation: N/A — 沿用 Godot 场景绘制与 canonical 建设命令。
Dependencies: story-012-war-interface.md — Complete

用户要求历史感来自结构。本轮在独立 Godot 仓库把城内散放建筑改为城门主街、官署庭院与四坊道路，把民居、市场、军营与仓储绘成不同用途院落；场景不为重新分区而搬移实际地块。城外资源地由按钮清单改为有水渠、农田、林地和采掘地的可选择场景。参照汉代坊市、夯土城墙资料作游戏构图，不声称精确复原某座历史城池。既有经济、建设时间和存档兼容。

## 验收

- [x] 城门和主街形成连续空间，官署、民居、坊市和军务场地有不同院落与轮廓；不是边框换色。
- [x] 场景只把真实已建记录绘成建筑，重复建筑和空地精确对应实际 site，保留地不作为可建空地；旧选择不会操作另一处建筑。
- [x] 城外道路、水渠和地貌连接真实地块，显示已有资源类型、等级与施工状态；锁定地块不可操作。
- [x] 城内/城外场景优先，城务与样板折叠后仍能访问；选中具体地块后显示该处的费用、耗时与建设操作。
- [x] 1280 与 390 布局、触控命中、轮询/城池切换、pending/断线和原命令参数通过相关检查；实际桌面与 Web 场景观察、Windows/Web 导出有证据。

CCGS 配置已实际解析为 collaborative/minimal/coarse、qa minimal，testing.strict unset、system overrides none。ADR N/A，本轮无 TR/control manifest。三个子代理分别绘制城内、城外及只读核对，root 整合、真实运行和导出。测试使用隔离数据；公网手机入口仍待用户单独批准。

## 最终结果

0.6.0-dev.7源场景已经冻结；城内固定实际site、重复建筑与裸空地，城外真实index地景、场景优先和折叠城务已整合。两类场景的点击改为松手确认，滚动、取消、多指与模拟鼠标不会打开建设；独立真实Viewport→ScrollContainer链路验证24项headless＋24项macOS原生通过。

城外空地四种用途分别显示权威首级费用、工期与门槛，全建设队列时禁用操作；最终相关11个GDScript入口4912项通过、Node31项通过、macOS原生主整合69项通过，独立最终源码复查无阻断。Windows/Web已最终导出，241项包检查通过（归档174、两PCK各26、Web HTTP15）；两PCK由macOS加载连接解包规则服务，Windows EXE没有在Windows实机运行。

实际最终Web1280×1000/390×844已观察城内、精确空地36、城外12处开放地块、3号空地四用途报价、下部按钮/样板与南门滚动，未提交消费，revision0。服务重启时旧客户端有一次Failed to fetch，最终06:34:02.580Z重载后warning/error0；不把历史瞬断隐去。17355使用17351进度副本，旧进度保留。物理手机未运行。

最终报告为[历史空间结构报告](../../polish/historic-city-report-2026-10-07.md)，聚合证据为[qa-summary.json](../../qa/evidence/story-013/qa-summary.json)和[package-audit-summary.json](../../qa/evidence/story-013/package-audit-summary.json)，最终字节数和SHA256见同目录build-manifest.json。prepared developed截图为展示用fixture，不是自然成长。本轮本地交付，main HEADc6b96d0，009–013工作区未提交，不推送或公开Release。
