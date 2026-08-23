# M2-08a Provider Configuration 统一迁移

## 目标

把现有散落在 `AppSettings` 的 ASR 路由、Endpoint、模型和数据位置收敛为一个可编码的 `ASRProviderConfiguration`，让 Runtime 能以同一份配置解释当前路由，同时保持旧设置文件和现有 UI/测试兼容。

## 范围

- 新增本机优先/本机模型/外部服务的统一 ASR 配置值对象。
- 旧 `asrProviderSelection`、`asrEndpoint`、`asrModel`、`asrAPIKey` 访问保留为兼容门面，内部转发到统一配置。
- 新写入的设置只保存 `asrConfiguration`；旧设置文件首次读取时自动迁移。
- API Key 仍只从 Keychain 加载，不写入设置 JSON；配置值对象的 API Key 字段只存在于内存。
- 为配置提供稳定的 Provider ID、传输方式、数据位置和是否已配置判断，供后续 Registry/Health 使用。

## 非目标

- 本任务不新增 Provider 市场、任意动态库或 Agent 入口。
- 不改变本机/外部 ASR 的选择语义、外发确认和录音/Job 流程。
- 不把 LLM 配置并入 ASR；LLM 继续使用现有兼容路径。

## 数据契约

`ASRProviderConfiguration` 至少包含：

- `selection`：`automatic`、`onDevice`、`external`。
- `endpoint`、`modelID`：外部 HTTP 配置；Endpoint 为空时表示没有外部服务。
- `apiKey`：内存字段，编码时必须省略。
- 派生 `effectiveProviderID`、`transport`、`dataLocation`、`isConfigured`。

## 兼容与安全

- 能读取只含旧字段的设置 JSON，并恢复等价行为。
- 新编码结果包含 `asrConfiguration`，不包含 `asrAPIKey` 的明文。
- 普通设置保存不触碰 Keychain；只有 API Key 变化时才单独写入既有账号。
- 原始音频、Transcript、ProcessingTask 和外部确认队列不受迁移影响。

## 验收标准

- 旧设置 JSON 解码后，四个兼容访问器与迁移前值一致。
- 新设置编码后可以再次解码，配置值保持一致，JSON 不出现 `asrAPIKey`。
- Endpoint、模型、选择方式的现有设置 UI 和 101 项既有测试不回归。
- `make docs-check harness-check`、目标测试和完整 `make verify` 通过。
