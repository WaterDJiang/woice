# 原文显示清理与品牌资产接入规格

状态：已实现，待桌面 UI 人工验收  
日期：2026-08-22

## 1. 背景与目标

WhisperKit 的控制 token 和时间 token 目前会直接出现在历史列表、录音详情的“原文”、复制内容和导出 Markdown 中，用户看到的是模型协议，而不是可用素材。本规格要求在不改写既有原始 Artifact 的前提下，统一提供干净的文本投影；时间戳仍由独立的“时间戳片段”区域承载。

同时，将已确认的 Woice W 折叠波形 PNG 资产纳入 SwiftPM 资源和发布包，作为菜单栏闲置态品牌标识、窗口品牌标识和运行时 Dock 图标。

## 2. 范围

### 包含

- 在 Domain 层提供确定性的 Whisper token 清理器，移除 `<|...|>` 控制/时间标记，保留正文和换行。
- WhisperKit 与 OpenAI-compatible ASR Provider 在边界处清理新结果；已有持久化记录在 UI、复制、导出和 Connector 读取时使用只读清理投影。
- 原文详情、历史标题/搜索、复制、Markdown 导出和 Agent 上下文不再展示协议 token。
- 继续显示 `TranscriptSegment.start/end`，不把时间信息混进正文。
- 将 `assets/brand/exports/woice-app-icon-64.png` 纳入 SwiftPM 资源；发布脚本额外复制 1024px 图标到 App Resources。
- 菜单栏闲置态、Popover 标题和运行时应用图标使用品牌 PNG；录音中的红色状态图标和文字保持不变。

### 不包含

- 不删除、不覆盖、不迁移既有原始 transcript 字段。
- 不重新绘制、改色、裁切或生成未经验证的 `.icns`。
- 不改变转写时间戳数据模型，不把 TTS 或 Agent 能力并入录音原文链路。

## 3. 设计与边界

- `TranscriptTextNormalizer` 是纯函数投影；Provider 新结果在写入前清理，历史记录在读取/显示时清理。
- 时间 token 被清理，真实的 `TranscriptSegment` 时间仍持久化并在片段列表中可点击播放。
- 清理后的空文本按原有空结果错误处理；不以“有 token”冒充有效转写。
- App 资源从已确认的 `assets/brand/exports` 尺寸族复制，源资产保持单一生产真相。
- SwiftPM 资源编译进 App target；运行时按 `Bundle.main` 的标准 `Contents/Resources` 路径读取，`App.init` 设置 `NSApplication.shared.applicationIconImage`，发布脚本同步携带大尺寸 PNG。

## 4. 验收标准

- AC-TEXT-001：给定截图中的 Whisper 控制/时间 token，原文正文、历史标题、复制文本和导出 Markdown 不含 `<|...|>`，中文句子顺序与内容保持不变。
- AC-TEXT-002：时间戳片段仍显示 `00:00` 等起始时间，点击仍按原始 `start` 播放；片段文本本身不显示 token。
- AC-TEXT-003：旧记录不被持久化重写；读取后 UI 和 Connector 得到清理投影，原始字段哈希不变。
- AC-TEXT-004：WhisperKit、HTTP JSON 和纯文本 ASR 结果分别通过单元测试，控制 token 不会进入新保存结果。
- AC-BRAND-001：SwiftPM 构建和发布包能从 App Resources 加载 Woice PNG；菜单栏闲置态和 Popover 标题可见品牌图形，具备 VoiceOver 文本“Woice”。
- AC-BRAND-002：Core/Offline 发布包的 `Contents/Resources` 含 1024px Woice 图标，签名和现有资源校验继续通过。
- AC-BRAND-003：录音态仍以红色录音图标、时长和文字表达状态；浅色、深色和 Reduce Motion 不引入额外动画。

## 5. 替代、保留、迁移、停止、顺序

- 替代：替代 UI 直接渲染 Provider 原文的做法；由清理投影统一输出。
- 保留：原始音频、持久化 transcript、真实时间戳、既有 AppIcon Asset Catalog 和品牌母版。
- 迁移：旧记录只在读取/导出路径获得清理投影，不做破坏性数据库迁移。
- 停止：停止在正文区域显示 Whisper 协议 token；停止将未经清理的正文复制给用户或 Connector。
- 顺序：先实现清理器和 Provider 边界，再接入 UI/导出/Connector，最后接入资源包、发布脚本和安装验证。

## 6. 失败处理

- 资源缺失时显示系统图标回退并写入脱敏诊断，不阻塞录音、转写或历史访问。
- 清理器异常（理论上仅为实现错误）不得吞掉转写失败；通过单元测试和 `make verify` 直接暴露。
