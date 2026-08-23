# M2-05 PI Connector 协议边界

> 状态：版本化协议基础本轮实现；实际 PI Extension 需在依赖锁定后接入

## 1. 目标

为 PI Extension 提供稳定、最小、只读优先的本地连接协议；PI 只能调用版本化 Woice RPC，不得直接访问 Swift 内部类型、SQLite 或音频设备。

## 2. 范围

- 冻结协议版本、请求 ID、允许的方法、参数和结构化错误。
- 允许查询状态、列出历史、读取转录、触发文本处理；录音开始仍需 Woice 用户手势。
- 每个高风险外发/处理动作携带 `requiresUserConfirmation`，由 Woice UI 决定是否弹确认。
- 为未来 `registerTool`、`registerCommand("voice")`、`registerShortcut` 保留薄适配边界。
- App 内先实现 `PiConnectorRouter`，真实处理请求只返回“等待用户确认”，不直接发送网络请求。

## 3. 不在本工作包

- 不引入或下载 `@earendil-works/pi-coding-agent`，不在当前 SwiftPM App 内嵌 Node runtime；本轮先完成 Swift Router，Extension 仍独立接入。
- 不实现 PI Extension 的发布、版本兼容矩阵或自动安装。
- 不暴露 `woice_record_start` 的静默调用，不让 Connector 绕过录音策略。

## 4. 验收标准

- 合法请求/响应可 Codable 编解码，未知方法和缺少协议版本 fail-closed。
- 协议对象不携带 API Key、音频 base64 或无限长文本。
- `make verify` 通过，PI 契约测试覆盖只读方法和用户手势约束。
