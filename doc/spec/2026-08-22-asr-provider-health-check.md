# 自定义转写 API 健康检查

## 目标

让用户在保存设置前验证自定义 OpenAI-compatible ASR 地址、模型和授权是否可达，减少录音结束后才发现配置错误的等待成本。

## 安全边界

- 健康检查必须由用户点击“测试转写 API”主动触发。
- 只发送 Woice 在本机生成的短测试 WAV，不读取历史录音、不发送用户语音、不创建历史 RecordingRecord。
- 界面明确显示目标主机和“不会发送历史录音”；API Key 仍只从当前草稿传入内存请求，不写日志。
- 检查只验证 HTTP 成功响应和请求契约，不把测试响应保存为转写原文。

## 验收标准

- Endpoint 非法或模型为空时按钮禁用，并显示可修正提示。
- 点击后显示进行中状态；成功响应显示主机和 HTTP 状态，失败显示脱敏后的可执行错误。
- 测试使用与正式录音相同的 `/audio/transcriptions` multipart、模型、语言和 Bearer 头。
- 测试不会改变草稿、已保存设置、历史记录或外发确认队列。
- `make verify` 与 `make acceptance-core` 继续通过。

## 影响面

- `TranscriptionClient`：增加只验证 HTTP 响应的健康检查入口，复用正式 multipart 请求构造。
- `AppState`：生成短暂本机测试 WAV 并调用健康检查，不修改状态或历史。
- `SettingsView`：在语言转文字设置区增加测试按钮、进行中和结果文案。
- `LoopbackASRHTTPTests`：用真实本机 TCP listener 验证 2xx（含 204 空响应）和正式 multipart 请求契约。
