# plan/ 索引

- MRQ-07 已加入 [MRQ 计划](2026-09-01-material-naming-durability-detail-performance-qwen-quality.md)：Qwen 短读崩溃修复、真实模型回归和 Dev 安装已完成。

实施前先读[当前路线图与计划迁移表](2026-08-22-current-roadmap-and-plan-transition.md)。它是唯一跨计划状态源；专项计划只管理自己的工作包，不得改变全局顺序。

| 阶段/文件 | 状态 | 目标与边界 | 文件 |
|---|---|---|---|
| 主界面录音控制、外放回声与工作台美化 | REC-01 代码已实现；真实 Dev 界面验收待稳定签名 | 工作台持续显示录音状态和停止入口；回声方案通过独立质量门禁后集成，不重开 MRQ 已完成项 | [优化计划](2026-09-08-recording-controls-echo-and-workspace-polish.md) |
| 当前路线图 | 生效，唯一跨计划状态源 | 裁决旧计划的继续、迁移、冻结、停止和实施顺序；不创建重复工作包 | [2026-08-22-current-roadmap-and-plan-transition.md](2026-08-22-current-roadmap-and-plan-transition.md) |
| 素材命名、耐久性、详情性能与 Qwen 输出质量 | MRQ-00～06 自动代码/工程门禁完成；MRQ-06 稳定签名 Dev 已安装启动；真实桌面、会议与发行外部门禁仍待 | 会议默认合并音频单次转写；保留双原轨和高级分轨选项，避免 Qwen 默认转写两次并把两轨内容合并进 Markdown | [2026-09-01-material-naming-durability-detail-performance-qwen-quality.md](2026-09-01-material-naming-durability-detail-performance-qwen-quality.md) |
| 录音与转写产品升级门禁 | 已合并，非独立排期源 | 只保留竞品/UI 证据与历史验收；会议默认策略以 2026-09-07 MSP 规格的合并音频单次转写为准 | [2026-08-22-recording-product-upgrade.md](2026-08-22-recording-product-upgrade.md) |
| R0 核心收口 | 源码与自动门禁已收口，真实 Mac Journey 仅作提醒 | 录音、自动中断安全保存、录音磁盘预检和素材安全已有代码证据；休眠/设备变化/崩溃/磁盘矩阵与视觉/TCC 复验不再作为开发工作包 | [旧总计划的有效工作包](2026-08-22-m0-mvp.md) |
| M2-08 | 既有闭环完成；Qwen Runtime/模型包已落地，输出正确性与性能迁入 MRQ；发行仍有外部条件 | 保留现有 ASR/WhisperKit/Core/Offline；Qwen tokenizer/质量/性能由 MRQ 承接，签名 Catalog 和 Developer ID 仍按专项发行门禁推进 | [2026-08-22-model-integration.md](2026-08-22-model-integration.md) |
| R2 素材库收口 | 代码与自动门禁已收口，真实桌面 Journey 仅作提醒 | 历史、搜索、复听、开放导出、Artifact 来源链和“素材可用”状态已有实现，不新增并行工作包 | [迁移表 R2](2026-08-22-current-roadmap-and-plan-transition.md#r2素材库收口) |
| M2-09 | 源码与契约门禁已完成，保持 Beta 与核心发布后置 | 将已完成素材发送给已验证的外部 Agent，并允许 Agent 在授权范围内读取 Woice 上下文；真实 CLI 登录、批准、素材入站和外部 Journey 仅作人工提醒，不承诺所有 CLI | [2026-08-22-voice-context-agent-integration.md](2026-08-22-voice-context-agent-integration.md) |
| 工作区侧栏与权限连续性优化 | 历史实施与证据记录，无活动待办 | 保留已完成实现与证据；剩余技术缺口迁入 WCL，真实用户和人工体验只作提醒 | [2026-08-23-workspace-sidebar-and-permission-continuity.md](2026-08-23-workspace-sidebar-and-permission-continuity.md) |
| 当前技术开发收口 | 已结项为历史；无活动工作包 | 已完成证据继续有效；Qwen 正确性/性能迁入 MRQ，Developer ID 和 Store 外部条件分别保留在发行路线与 MAS 专项 | [2026-08-24-current-technical-development-closure.md](2026-08-24-current-technical-development-closure.md) |
| 菜单栏、设置、快捷键与 Dock 图标精简优化 | MSS-07R 代码与自动测试完成；真实 Mac Journey 待用户验收 | Popover、四动作、设置、快捷键、AppIcon、来源命名、loopback 信任持久化、工作台确认、可恢复“稍后处理”、主/片段任务去重和活动转写状态投影已落地；专项工作台证据保留于 Build `2026082332`，当前安装包为源码构建 `0.1.0 (Build 1)`，真实录音、长文件和云端 Provider 完成仍按手册实测 | [2026-08-23-menubar-settings-shortcut-optimization.md](2026-08-23-menubar-settings-shortcut-optimization.md) |
| 当前计划进度复核 | 历史快照 | 保留 2026-08-25 前既有基线与 WCL 证据；2026-09-01 后活动状态以 MRQ 为准 | [2026-08-23-plan-progress-review.md](2026-08-23-plan-progress-review.md) |
| Mac App Store 上架 | `0.1.4 (Build 9)` 已通过审核并正式发布到已配置的 175 个国家或地区，App Store Connect 状态为“可分发” | 单一 Store Edition 已完成首发；后续版本仍沿用审核、手动发布与隐私门禁，不替代官网 Core/Offline 的 Developer ID/公证计划 | [2026-08-23-mac-app-store-launch.md](2026-08-23-mac-app-store-launch.md) |
| M0-M3 旧总计划 | 历史执行基线，部分范围已迁移或停止 | 保留已实现记录与仍有效的录音工作包；不能单独作为当前排期依据 | [2026-08-22-m0-mvp.md](2026-08-22-m0-mvp.md) |
| 旧 M3 生态 | 已停止，不得执行 | DeepSeek 可在契约明确后作为 M2-09 P1 专用适配评估；插件市场/网关计划失效 | [迁移裁决](2026-08-22-current-roadmap-and-plan-transition.md#3-旧计划迁移矩阵) |

规则：新计划未写清“替代、保留、迁移、停止、顺序”五项时，只能标为草案。
