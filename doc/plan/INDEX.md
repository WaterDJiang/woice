# plan/ 索引

实施前先读[当前路线图与计划迁移表](2026-08-22-current-roadmap-and-plan-transition.md)。它是唯一跨计划状态源；专项计划只管理自己的工作包，不得改变全局顺序。

| 阶段/文件 | 状态 | 目标与边界 | 文件 |
|---|---|---|---|
| 当前路线图 | 生效，唯一跨计划状态源 | 裁决旧计划的继续、迁移、冻结、停止和实施顺序；不创建重复工作包 | [2026-08-22-current-roadmap-and-plan-transition.md](2026-08-22-current-roadmap-and-plan-transition.md) |
| 录音与转写产品升级门禁 | 已合并，非独立排期源 | 只保留竞品/UI 证据与验收门禁；会议默认 meetingMix 单次 ASR，来源分离为可选模式，实施继续并入现有 M1/M2 工作包 | [2026-08-22-recording-product-upgrade.md](2026-08-22-recording-product-upgrade.md) |
| R0 核心收口 | 进行中，核心麦克风 UI Journey、自动中断安全保存、录音磁盘预检和部分音频保留基础已实现 | 系统音频当前安装包 TCC 复验、素材安全、休眠/设备变化/崩溃/磁盘矩阵和发布基础；不含新 LLM/Agent 能力 | [旧总计划的有效工作包](2026-08-22-m0-mvp.md) |
| M2-08 | 核心代码与本机发行切片已完成，正式发布与真实会议准确率仍待 | ASR Registry、macOS on-device、WhisperKit、模型包/下载、连接向导、Catalog 信任/回滚/轮换和 Core/Offline 双发行；系统音频权限新增当前安装包重新授权诊断 | [2026-08-22-model-integration.md](2026-08-22-model-integration.md) |
| R2 素材库收口 | 排在 M2-08 后，开放导出基础已实现 | 历史、搜索、复听、开放导出、Artifact 来源链和“素材可用”状态 | [迁移表 R2](2026-08-22-current-roadmap-and-plan-transition.md#r2素材库收口) |
| M2-09 | 进行中（两个真实 CLI 出站、本机 MCP 与 Claude 合成入站已验证），Codex 交互批准、真实素材入站与权限矩阵待 | 将已完成素材发送给已验证的外部 Agent，并允许 Agent 授权读取 Woice 上下文；不承诺所有 CLI，不改变录音核心定位，也不作为核心发布前置 | [2026-08-22-voice-context-agent-integration.md](2026-08-22-voice-context-agent-integration.md) |
| 工作区侧栏与权限连续性优化 | 代码已完成，真实 Mac 验收待用户完成 | 单一侧栏、音视频导入连续转写、双击启动工作台、素材来源/空状态和权限代码已落地；稳定签名 A/B、启动/AX/快捷键和此前同身份权限连续性已通过；正常音频导入、损坏视频、无音轨视频和任务状态 VoiceOver 投影的隔离桌面边界已通过；逐项授权、完整视觉/无障碍矩阵、真实长文件和真实 Provider 仍待用户手动验收；CLI Beta 未完成项集中列在计划末尾 | [2026-08-23-workspace-sidebar-and-permission-continuity.md](2026-08-23-workspace-sidebar-and-permission-continuity.md) |
| 菜单栏、设置、快捷键与 Dock 图标精简优化 | MSS-07R 代码与自动测试完成；稳定签名 A/B 已覆盖安装；真实 Mac Journey 待用户验收 | Popover、四动作、设置、快捷键、AppIcon、来源命名、loopback 信任持久化、工作台确认、可恢复“稍后处理”、主/片段任务去重、动态文案、导入页、处理任务、侧栏和可继续入口活动转写状态投影已落地；当前 Build B `2026082332`，真实录音、长文件和云端 Provider 完成仍按手册实测 | [2026-08-23-menubar-settings-shortcut-optimization.md](2026-08-23-menubar-settings-shortcut-optimization.md) |
| 当前计划进度复核 | 2026-08-23 已复核 | 自动门禁、稳定 A→B 签名覆盖、正常/失败音视频 Fixture 桌面导入、任务状态 VoiceOver 投影、QuickTime 系统音频和启动/AX/键盘证据已更新；真实用户素材长文件、逐项授权、完整视觉/无障碍、长时稳定性、发行和 CLI Beta 仍未关闭 | [2026-08-23-plan-progress-review.md](2026-08-23-plan-progress-review.md) |
| Mac App Store 上架 | 待实施，等待用户按需启动 | 单一 Store Edition 的 Xcode Archive、App Sandbox、能力裁剪、隐私/素材、TestFlight 和审核；不替代官网 Core/Offline 的 Developer ID/公证计划 | [2026-08-23-mac-app-store-launch.md](2026-08-23-mac-app-store-launch.md) |
| M0-M3 旧总计划 | 历史执行基线，部分范围已迁移或停止 | 保留已实现记录与仍有效的录音工作包；不能单独作为当前排期依据 | [2026-08-22-m0-mvp.md](2026-08-22-m0-mvp.md) |
| 旧 M3 生态 | 已停止，不得执行 | DeepSeek 可在契约明确后作为 M2-09 P1 专用适配评估；插件市场/网关计划失效 | [迁移裁决](2026-08-22-current-roadmap-and-plan-transition.md#3-旧计划迁移矩阵) |

规则：新计划未写清“替代、保留、迁移、停止、顺序”五项时，只能标为草案。
