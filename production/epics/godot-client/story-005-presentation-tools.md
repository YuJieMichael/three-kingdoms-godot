# 故事 005：声音、菜单与剧情工具

状态：IMPLEMENTED / 待审阅合并。日期：2026-10-06。分支：feat/presentation-tools。

用户范围：优先引入声音、菜单和剧情工具，现有战斗与数据系统继续沿用。

已集成固定提交的 Sound Manager 与 Dialogue Manager，以及 Maaack 独立菜单分页组件。新菜单复用原有设置/存档/连接入口；新增三类声音设置和可选的新手分支引导。音乐与提示音为自制合成演示，正式配乐尚待选定。MIT 来源和许可证完整保留，打包脚本复制许可证到 Windows/Web 包。

验证：全新缓存首次导入无脚本错误；675 项原 Godot 检查、40 项新检查通过。非 headless Windows 原生新检查通过，实际渲染截图确认 1280 与 390 宽度。Node 规则测试 21 项通过，符号链接测试在本机因 EPERM 创建失败。Windows/Web release 导出通过，官方引擎加载 Windows PCK smoke 通过。实际 Web 菜单、剧情分支、静音保存、390 窄屏和刷新持久化通过，控制台 warn/error 为空。

限制：自动审批拦截导出 Windows EXE 启动；没有 EXE 实际启动证据。未测试真实手机音频解锁、人工听感或长局；未发布新版本。规则桥接、原规则快照、地图数据与原仓库不变。

实现与操作说明见 docs/PRESENTATION-TOOLS.zh.md。

交付：[草稿 PR #1](https://github.com/YuJieMichael/three-kingdoms-godot/pull/1)。[Windows CI](https://github.com/YuJieMichael/three-kingdoms-godot/actions/runs/37488545553) 在实现提交 1dbce92 全绿，22 项规则＋715 项 Godot 检查，共 737 项；本机权限受阻的符号链接用例在 CI 中通过。
