# plan/ 索引

实施前先读[当前路线图与计划迁移表](2026-08-22-current-roadmap-and-plan-transition.md)。它是唯一跨计划状态源；专项计划只管理自己的工作包，不得改变全局顺序。

| 阶段/文件 | 状态 | 目标与边界 | 文件 |
|---|---|---|---|
| 当前路线图 | 生效，唯一跨计划状态源 | 裁决旧计划的继续、迁移、冻结、停止和实施顺序；不创建重复工作包 | [2026-08-22-current-roadmap-and-plan-transition.md](2026-08-22-current-roadmap-and-plan-transition.md) |
| 录音与转写产品升级门禁 | 已合并，非独立排期源 | 只保留竞品/UI 证据与验收门禁；会议默认麦克风/系统音频来源分离后分别转写并合并，`standardMix` 仅为显式兼容模式，实施继续并入现有 M1/M2 工作包 | [2026-08-22-recording-product-upgrade.md](2026-08-22-recording-product-upgrade.md) |
| R0 核心收口 | 源码与自动门禁已收口，真实 Mac Journey 仅作提醒 | 录音、自动中断安全保存、录音磁盘预检和素材安全已有代码证据；休眠/设备变化/崩溃/磁盘矩阵与视觉/TCC 复验不再作为开发工作包 | [旧总计划的有效工作包](2026-08-22-m0-mvp.md) |
| M2-08 | 核心代码与本机发行切片已完成，WCL-04 正式发行验证待凭据 | ASR Registry、macOS on-device、WhisperKit、模型包/下载、连接向导、Catalog 信任/回滚/轮换和 Core/Offline 双发行；Developer ID/公证/生产 Catalog/远程产物读回和人工会议矩阵按 WCL 记录 | [2026-08-22-model-integration.md](2026-08-22-model-integration.md) |
| R2 素材库收口 | 代码与自动门禁已收口，真实桌面 Journey 仅作提醒 | 历史、搜索、复听、开放导出、Artifact 来源链和“素材可用”状态已有实现，不新增并行工作包 | [迁移表 R2](2026-08-22-current-roadmap-and-plan-transition.md#r2素材库收口) |
| M2-09 | 源码与契约门禁已完成，保持 Beta 与核心发布后置 | 将已完成素材发送给已验证的外部 Agent，并允许 Agent 在授权范围内读取 Woice 上下文；真实 CLI 登录、批准、素材入站和外部 Journey 仅作人工提醒，不承诺所有 CLI | [2026-08-22-voice-context-agent-integration.md](2026-08-22-voice-context-agent-integration.md) |
| 工作区侧栏与权限连续性优化 | 历史实施与证据记录，无活动待办 | 保留已完成实现与证据；剩余技术缺口迁入 WCL，真实用户和人工体验只作提醒 | [2026-08-23-workspace-sidebar-and-permission-continuity.md](2026-08-23-workspace-sidebar-and-permission-continuity.md) |
| 当前技术开发收口 | 唯一活动开发计划；双音源、AAC/M4A、会议合成、长详情按需加载与录音控制视觉层级增量完成，官网 208 项 / 14 Suite、Store 186 项 / 11 Suite 通过；WCL-04 发行验证与 WCL-06 签名 Archive 仍待外部条件 | WCL-00～06 只承接代码、自动测试、发行工程、Agent 安全和 MAS 工程；真实用户、真实会议与人工体验仅作提醒 | [2026-08-24-current-technical-development-closure.md](2026-08-24-current-technical-development-closure.md) |
| 菜单栏、设置、快捷键与 Dock 图标精简优化 | MSS-07R 代码与自动测试完成；真实 Mac Journey 待用户验收 | Popover、四动作、设置、快捷键、AppIcon、来源命名、loopback 信任持久化、工作台确认、可恢复“稍后处理”、主/片段任务去重和活动转写状态投影已落地；专项工作台证据保留于 Build `2026082332`，当前安装包为源码构建 `0.1.0 (Build 1)`，真实录音、长文件和云端 Provider 完成仍按手册实测 | [2026-08-23-menubar-settings-shortcut-optimization.md](2026-08-23-menubar-settings-shortcut-optimization.md) |
| 当前计划进度复核 | 2026-08-25 已更新 | 双音源、AAC/M4A、长详情与录音控制视觉层级增量完成；官网版 `make verify` 通过 208 项 / 14 个 Suite，Store 条件通过 186 项 / 11 个 Suite，正式 Xcode Store 无签名构建通过；真实会议声源和 50 分钟素材由用户人工复验 | [2026-08-23-plan-progress-review.md](2026-08-23-plan-progress-review.md) |
| Mac App Store 上架 | MAS-03、正式 Xcode Store 组合根和本机打包/隐私/沙盒静态预检已完成；MAS-00～02、MAS-04～08 的正式工作包待决策/外部条件 | 单一 Store Edition 的签名 Archive、正式 App Sandbox 运行、模型/隐私审定、TestFlight 和审核；不替代官网 Core/Offline 的 Developer ID/公证计划 | [2026-08-23-mac-app-store-launch.md](2026-08-23-mac-app-store-launch.md) |
| M0-M3 旧总计划 | 历史执行基线，部分范围已迁移或停止 | 保留已实现记录与仍有效的录音工作包；不能单独作为当前排期依据 | [2026-08-22-m0-mvp.md](2026-08-22-m0-mvp.md) |
| 旧 M3 生态 | 已停止，不得执行 | DeepSeek 可在契约明确后作为 M2-09 P1 专用适配评估；插件市场/网关计划失效 | [迁移裁决](2026-08-22-current-roadmap-and-plan-transition.md#3-旧计划迁移矩阵) |

规则：新计划未写清“替代、保留、迁移、停止、顺序”五项时，只能标为草案。
