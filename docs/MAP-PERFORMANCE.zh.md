# 地图性能测量与复现

本轮采用 pc-games 的先测量再优化及 CCGS `perf-profile`。基准只实例化 Godot 地图，使用隔离的合成 DTO，不连接规则桥接、不加载或写入玩家存档。优化前、第一轮和最终优化后三次非 headless 捕获已完成且有效，两份比较均 matched；数值及限制见 [2026-10-06 性能报告](../production/polish/world-map-report-2026-10-06.md)。故事 004 的实际导出观察、资产校验及正式 Windows 包启动 CI 亦已完成，见 [验证记录](QA.zh.md)；这些功能与启动证据不代替目标平台性能测量。

原始逐帧 JSON 归档为 [before](../production/polish/data/map-before-2026-10-06.json)、[first after](../production/polish/data/map-after-first-2026-10-06.json)、[final after](../production/polish/data/map-after-2026-10-06.json)；比较为 [first comparison](../production/polish/data/map-comparison-first-2026-10-06.json) 与 [final comparison](../production/polish/data/map-comparison-2026-10-06.json)。第一轮三种 CPU 尾部回退保留供审计，最终数据来自后续代码优化，没有拼接各轮最佳场景。

## 原生基准

在本仓库运行，使用项目实际采用的 Godot 4.7.2 标准版。计时必须使用非 headless 的原生窗口；脚本会拒绝 headless 与 Web 性能计时。运行时保留窗口大小和固定视口，不移动／改变基准摄像机或修改源码；尽量保持同一设备、显示器、供电和后台负载。

```sh
"/Users/lihuazeng/Documents/Codex/2026-10-05/e/tools/godot-4.7.2/Godot.app/Contents/MacOS/Godot" \
  --path . --script scripts/map_profile.gd -- \
  --label before --output .local/performance/map-before.json \
  --warmup 30 --frames 150
```

优化后使用同一命令，仅更换标签与输出文件：

```sh
"/Users/lihuazeng/Documents/Codex/2026-10-05/e/tools/godot-4.7.2/Godot.app/Contents/MacOS/Godot" \
  --path . --script scripts/map_profile.gd -- \
  --label after --output .local/performance/map-after.json \
  --warmup 30 --frames 150
```

`before` 和 `after` 标签本身不会切换源码。必须在优化前后相应源码上执行，保存 JSON 中的 `source_sha256` 与 `harness_sha256`，不能对同一份优化后源码改标签后称为优化前数据。若要复现旧版本，在独立检出目录使用旧版地图源码和同一份基准脚本，保持相同采样参数；不要回退正在运行的玩家工作区。

可通过 `--scenario 64_pan` 等参数仅运行一个场景；所有输出限制在该检出的 `.local/performance/` 内。基准使用固定 seed `439903`，视口为 1280×800，开启 VSync 并限帧 60。这里的限帧是实验条件，不是项目性能预算。行军使用真实时钟的相对 48 小时行程，以便动画运行而镜头几何近似一致。

| 场景参数 | 世界 DTO | 缩放 | 行军条数 | 镜头 |
|---|---|---|---|---|
| `64_static` | 64×64 | 0.80 | 0 | 静止 |
| `64_pan` | 64×64 | 0.80 | 0 | 固定帧索引路径 |
| `256_overview_pan` | 合成 256×256 | 0.17 | 0 | 固定帧索引路径 |
| `256_marches_pan` | 合成 256×256 | 0.80 | 200 | 固定帧索引路径 |
| `256_marches_idle` | 合成 256×256 | 0.80 | 200 | 静止 |

每次执行读取 `MAP_PROFILE_VALID=true` 并核对 JSON `valid`、源码在运行期间未变、视口未变。比较时核对 workload、种子、fixture hash、热身／采样帧数、视口、Godot、渲染方式、驱动与设备；失效捕获不得混入结果。需要多次捕获时另存输出，保留原始逐帧数据，不覆盖较慢的运行以挑选最好成绩。

使用独立比较工具生成结果：

```sh
python3 scripts/compare_map_profiles.py \
  .local/performance/map-before.json \
  .local/performance/map-after.json \
  --output .local/performance/map-comparison.json
```

工具拒绝环境、工作负载或逐帧镜头路径不一致的捕获；不能将拒绝结果作为 matched 比较。比较工具另有 14 项隔离检查，通过结果与 697 项游戏／地图检查分别记录。

已归档三次基准 SHA256 均为 `0222249719b1845686dc012adbbb1b62aa9f054f6110593ea04e60fd7542d461`；地图源码 before 为 `6fde79b3ad1a42a292297288dabb535a61ac1eb5edd21f9c4cfac6238682e3ea`，first after 为 `759e68ae86e30493f6f0c40c7f20b8833cc09fc57709dc6e935462576e12b425`，final after 为 `4d0fbb443343438e77d6a9b9194a019dec0562fb0c88b0d0673cf0c21cc90179`。仅修改说明、测试或发布配置不会代表地图实现改变；复现须核对实际地图文件哈希。

最终总览每次重绘 CPU p95 为 72.376→37.163 ms，但 64_pan 帧间隔 p95 为 67.432→67.678 ms，CANVAS calls 没有下降，200 行军拖动仍是每个采样帧两次重绘，单次世界快照准备更贵。不能将 CPU draw 改善扩写成所有帧指标改善或固定 FPS 达标。每类森林／山峰归一化几何缓存上限 2048，整体清空后的长局尾部与定期快照刷新待后续采样。

## 各指标的含义

- `draw_cpu_ms`：GDScript 生成绘制命令的 CPU 时间；包含基准插桩开销，不是 GPU 时间或完整帧耗时。
- `landform_cpu_ms`、`rivers_cpu_ms`、`marches_cpu_ms`、`tile_features_cpu_ms`：上述 CPU 绘制过程中的分层耗时，不能重复加到总绘制耗时上。
- `summary_per_redraw`：仅实际重绘的样本；`summary_per_frame`：包含没有重绘的采样帧。解释 idle 场景时两者必须区分。
- `frame_interval_ms`：两次实际采样之间的时间，包含 VSync、限帧、渲染和调度的影响；不是键盘或触摸响应延迟。
- `canvas_draw_calls`、`canvas_objects`：Godot 视口 CANVAS 的真实渲染计数；tile/route calls 是脚本工作量计数。
- `static_memory_bytes`、`static_memory_peak_bytes`：Godot 整个 debug 进程的引擎内存监视值，不是地图独占内存，也不等于操作系统 RSS。峰值可能继承之前场景的分配，不能用前后两个场景之差证明地图泄漏。
- `set_world_cpu_ms`：合成世界 DTO 的复制／索引准备，不能代表网络请求或游戏加载时间。
- GPU 时间：UNAVAILABLE；当前基准不提供。无法通过 CPU 时间倒推出 GPU 时间或完整 FPS。

静态场景热身后零次重绘时，重绘统计的 count 为 0、分位数为空；初次绘制另存 `initial_draw`。空统计不表示首次绘图免费，也不是缺少渲染运行证据。

## 预算及适用范围

通过 `.claude/hooks/yaml-helper.sh resolve_config` 读取有效配置，当前 `performance.enforce` 是默认 `warn`。项目未设定 `performance.target_framerate`、`performance.frame_budget_ms`、`performance.draw_call_limit`、`performance.memory_ceiling_mb`；四项预算符合性均为 NOT ASSESSED — NO BUDGET，不能从模板填入 60 FPS、16.67 ms 或固定 draw-call 上限后宣布达标。

合成 256×256 不改变当前 canonical 64×64 世界；200 条合成行军不代表 200 名玩家、多人服务器能力或已实现扩州。开发机原生捕获不能代替 Windows/Web/真实手机性能验证；导出成功、headless 启动或数学回归检查也不能代替非 headless 测量。

本轮另有超长行军路线的确定几何缺陷：旧绘制从起点最多迭代 600×15 px；裁剪修复需保留两端屏外但穿屏的路线、原始虚线相位和部分可见标签。相应功能回归证据与性能数据分别记录，不能将“路线重新可见”描述为已测得的 FPS 收益。
