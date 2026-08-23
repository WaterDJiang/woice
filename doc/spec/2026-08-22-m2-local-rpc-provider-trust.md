# M2-05/M2-07 本地 RPC 传输与 Provider 信任验证

> 状态：基础实现完成，PI Extension 适配包已落地，待真实 PI 加载与发布签名验收

## 1. 目标

- 让 PI/其他本地 Connector 通过当前用户专属 Unix Socket 调用 Woice，而不是只在 App 内直接调用 Router。
- 让 Provider Manifest 的信任状态来自可验证的代码签名/来源检查，不由调用方任意填写 `signatureVerified`。
- 保持本地优先、用户控制录音、外发确认和 fail-closed 边界。

## 2. 本地 RPC 范围

- Socket 路径固定在 Woice Application Support 目录，启动前清理同路径陈旧节点，权限为当前用户可读写（0600）。
- 使用单请求单响应的 UTF-8 JSON Lines；单行最大 64 KiB，超限、无效 JSON、未知协议版本立即返回结构化错误并关闭连接。
- Server 只负责编解码、大小限制、超时和调用 `PiConnectorRouter`；不得读数据库、音频设备或 API Key。
- 只读方法可直接返回；处理方法仍由 Router 创建 `awaiting_user_confirmation`，Server 不绕过 AppState 的确认流程。
- 停止 App 或 Server 时关闭 Listener、删除 Socket 节点；重复启动不能抢占其他实例的 Socket。

## 3. Provider 信任范围

- `bundled` Provider 必须通过当前 App 签名团队标识检查；不匹配或无法读取签名时拒绝。
- `userInstalled`/`external` Provider 使用 `codesign --verify --deep --strict` 等价的 Security.framework 验证；unsigned 只允许在显式开发配置下运行。
- 验证结果包含来源、团队标识、签名状态和错误原因；结果不写入 API Key、Prompt 或音频内容。
- Manifest 的声明只能作为候选元数据，不能把 `trust = signatureVerified` 当成事实。

## 4. 不在本工作包

- 不实现 PI Extension 的 npm 发布、自动安装或任意第三方网络服务。
- 不允许 Provider 动态加载 dylib/bundle；只运行经过 Manifest 和信任门禁的可执行文件。
- 不把签名失败静默降级为云端 Provider 或绕过用户确认。

## 5. 验收标准

- Unix Socket 契约测试能启动 Server、发送 status/readTranscript、收到 Codable 响应，并验证 64 KiB 限制、坏 JSON 和重复启动保护。
- Socket 文件权限为 0600，停止后节点清理；Server 不暴露 API Key。
- Provider 签名验证对 `/bin/cat`、不存在路径和未签名临时 fixture 返回稳定状态；未通过验证的 Provider 不能进入 Runner。
- `make verify`、真实麦克风/ASR/双轨烟测和 Release 安装不回归。

## 6. 本轮实现证据

- `PiConnectorServer` 使用当前用户 Application Support 下的 POSIX Unix Socket，权限 0600；accept/read 在独立 utility 队列，`poll` 为半包和空闲连接提供 5 秒上限，Router 调用回到 MainActor。
- 单元测试覆盖 status/readTranscript、坏 JSON/超大请求、重复启动、Socket 清理和权限；真实安装包通过 `woice.status` JSON Lines smoke。
- `ProviderTrustVerifier` 使用 Security.framework 的静态代码签名有效性与可选 Team ID 校验；Runner 默认校验签名，unsigned 仅在显式 `allowUnsigned` 配置下允许。
- 尚未完成：真实 PI CLI 加载、Developer ID 签名、公证和真实第三方 Provider 的团队身份配置。
