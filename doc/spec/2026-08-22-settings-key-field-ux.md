# 设置页 API Key 字段体验

> 状态：基础实现完成；不改变密钥存储和外发策略。

## 目标

让服务设置页的 API Key 输入符合 macOS 常见设置体验：默认隐藏、用户主动显示、状态可被 VoiceOver 识别，且密钥仍只写入 Keychain。

## 验收标准

- ASR 与 LLM 两个 API Key 字段默认使用隐藏文本输入。
- 用户点击“显示 API Key”后才显示明文，再次点击可恢复隐藏。
- 显示/隐藏按钮有可读的 accessibility label 和 tooltip，不依赖图标颜色表达状态。
- 保存逻辑、Keychain 存储、日志脱敏和外发确认不改变。
- `make verify` 通过。
