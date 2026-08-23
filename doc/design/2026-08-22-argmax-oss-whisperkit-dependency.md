# Argmax OSS / WhisperKit 依赖决策

> 状态：M2-08c 依赖与 WhisperKit Tiny 权重闭环已验证；默认模型性能与发行仍未完成
> 日期：2026-08-22
> 关联：[M2-08 模型接入计划](../plan/2026-08-22-model-integration.md) · [双版本规格](../spec/2026-08-22-dual-edition-model-integration.md)

## 决策

- Swift Package Manager 使用 `https://github.com/argmaxinc/argmax-oss-swift.git` 的 `1.0.0` 精确版本；`Package.resolved` 锁定提交 `25c62997041c134b03ca82731ce2f6fd2cae1eb9`。
- Woice 只引入 `WhisperKit` product，不引入 SpeakerKit/TTSKit/ArgmaxOSS umbrella，避免把非录音核心能力带入应用。
- macOS 14+ 与 Swift 6 兼容是当前项目的最低门槛；WhisperKit 顶层类型不是 `Sendable`，只能留在 Provider Adapter 隔离边界，不能进入 Domain、Runtime 或 UI。
- 默认候选模型继续评估 `large-v3-v20240930_626MB`；当前可运行模型为官方 `openai_whisper-tiny`，不把 Tiny 的可运行证据等同于 large-v3 默认模型冻结。
- 当前真实验收锁定：模型仓库 `argmaxinc/whisperkit-coreml` revision `0f63a7800b00dd0226abd051b906c246e1907482`，目录 `openai_whisper-tiny`；tokenizer 仓库 `openai/whisper-tiny` revision `169d4a4341b33bc18d8881c4b69c2e104e1cc0af`。
- Woice 模型包会重新计算并保存每个文件 SHA-256，包含离线 tokenizer 和 `NOTICE.txt`，再通过原子 `current.json` 提交；当前真实 Tiny 包 23 个文件、79,400,945 字节。

## 许可证与供应链门禁

- Argmax OSS 主仓库声明 MIT；其仓库同时包含 vendored `swift-transformers` Hub/Tokenizers，按 Apache 2.0 记录，必须随应用保留上游 Notice。
- SwiftPM 解析出的传递依赖 `swift-argument-parser` 锁定 `1.8.2`，按其 MIT 许可证记录；它不是 Woice 运行时 Provider API，升级时仍需重新审计锁文件。
- Core/Offline ad hoc 产物现在生成依赖锁定记录、源码许可证、Notice 和 SBOM；正式 Offline 发布仍需完成签名 Catalog、性能基准、Developer ID/公证和干净机断网验收。
- 不把 WhisperKit 自动下载模型当作 Woice 模型包安装事实；模型必须经过 Woice 自己的清单、SHA-256、目录权限和原子 current 指针流程。
- 当前显式下载入口使用 WhisperKit Hub API 作为来源缓存；来源缓存不会直接成为 Provider，只有 Woice 清单校验和原子安装成功后才路由到 WhisperKit。

## 失败边界

- 依赖解析、编译或 Core ML 运行失败时响亮失败，继续保留 macOS on-device Speech 作为当前可运行 Provider；不得把失败伪装为 WhisperKit 已就绪。
- Provider 只接收已固化 WAV，返回 Woice `TranscriptionResult`；不直接写 Recording、SQLite 或设置。

## 验证来源

- https://github.com/argmaxinc/argmax-oss-swift/releases/tag/v1.0.0
- https://github.com/argmaxinc/argmax-oss-swift/blob/v1.0.0/LICENSE
- https://github.com/argmaxinc/argmax-oss-swift/blob/v1.0.0/NOTICES
- https://huggingface.co/argmaxinc/whisperkit-coreml/tree/0f63a7800b00dd0226abd051b906c246e1907482/openai_whisper-tiny
- https://huggingface.co/openai/whisper-tiny/tree/169d4a4341b33bc18d8881c4b69c2e104e1cc0af
