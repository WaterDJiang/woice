# 本机 ASR 模型版本与转写闭环规格

> 状态：M2-08 本机 Speech 与 WhisperKit Tiny 真实闭环已实现；默认模型性能与双发行门禁待完成
> 日期：2026-08-22
> 当前路线图：[计划迁移表](../plan/2026-08-22-current-roadmap-and-plan-transition.md)
> 专项计划：[M2-08 模型接入与双版本发布](../plan/2026-08-22-model-integration.md)

## 1. 目标

让 Woice 在没有外部 API 的情况下完成：

```text
用户开始录音 -> WAV 固化 -> 本机语言转文字 -> 原文保存 -> 历史详情可查看/播放/导出
```

本机 ASR 必须明确展示模型标识与版本，并把实际使用的模型快照写入转写任务，避免设置变化后无法追溯。

## 2. 范围

- Provider 只接受已经固化且可读的本机 WAV，不联网、不读取 API Key、不自动切换云端。
- `ProcessingTask` 保存 Provider、模型、版本和数据位置快照。
- 使用 macOS Speech 的 `requiresOnDeviceRecognition` 作为无 WhisperKit 模型时的本机 ASR Provider；已校验的 WhisperKit 模型包存在时优先使用 WhisperKit。
- 模型展示使用稳定 Provider ID、模型 ID、清单版本或系统版本和数据位置；任务快照必须与实际使用的 Provider 一致。
- 停止录音后自动开始本机转写；本机失败只保留原始录音并显示可重试错误，未授权时不在处理阶段重复触发系统弹窗。
- 设置页显示系统语音识别权限状态；首次授权只能由用户点击“允许”触发，拒绝或受限时说明原始录音仍安全保留。
- 设置页显示已安装模型清单，允许用户显式导入经过清单校验的模型目录；安装成功后立即切换本机 Provider。
- 设置页提供固定 revision 的官方 WhisperKit Tiny 显式下载；下载完成后离线 tokenizer、模型清单、文件 SHA-256 和 `current.json` 一起原子安装。
- 保留现有 OpenAI-compatible ASR；用户显式配置外部 Endpoint 时继续走外发确认流程。

## 3. 不在范围

- 不新增云端兜底、后台网络扫描、任意模型文件导入或动态库加载。
- 不把本机实时预览文本直接当作最终原文；最终原文来自停止后的本机文件转写结果。
- 不把没有完整基准证据的 WhisperKit Tiny 称为最终默认发行模型；当前 Tiny 仅作为已验证可运行的本机模型，large-v3/turbo 的默认选择、性能、许可证和发行门禁仍由 M2-08c 决定。
- WhisperKit Adapter 已锁定 `argmax-oss-swift` 1.0.0 并保持隔离；只有已安装且清单、大小、SHA-256 全部通过的包才会成为默认本机 Provider。

## 4. 验收标准

- 未配置外部 Endpoint 时，运行时使用本机模型作为安全 fallback；用户选择外部服务并填写 ASR Endpoint 后，外部 Provider 优先且仍需确认。
- 设置页显示本机模型名称、模型 ID、版本和“这台 Mac”；高级外部连接仍可编辑。
- 设置页能看到“等待授权/已允许/已拒绝/受系统限制”等本机语音识别状态；未决定时可以主动发起系统授权请求。
- 本机转写成功后，`RecordingRecord.transcript` 非空，原始 WAV 仍存在且可播放。
- 转写任务为 `completed`，并保存 `providerID`、`modelID`、`modelVersion`、`dataLocation=onDevice`。
- 本机 Provider 不可用或无有效文字时，任务为 `failed`，录音不被删除，也不发起外部请求。
- 当前模型文件被篡改、缺失或清单无效时，不进入 WhisperKit 路由并回退到 macOS Speech。
- 重试复用原始 WAV，并创建/更新同一幂等任务，不覆盖原始音频。
- 自动测试覆盖：模型版本稳定格式、设置兼容解码、Provider 成功/失败、任务快照持久化、外部 Endpoint 优先级。
- 显式真实验收覆盖：固定 WhisperKit revision 下载、离线 tokenizer、清单/SHA-256 原子安装，以及真实麦克风 -> WhisperKit -> 原文保存。
- 在已授权真实 Mac 上，人工完成至少一次“录音 -> 本机转写 -> 详情查看”；若 Speech 模型不可用，必须记录原始错误，不得写成通过。

## 5. 迁移裁决

- `替代`：当前“无 ASR Endpoint 即只保存录音”的默认分支。
- `保留`：外部 OpenAI-compatible ASR、首次外发确认、原始音频不可变和现有重试语义。
- `迁移`：未来 WhisperKit Provider 接入本机 ASR Provider 协议；不修改录音 Pipeline。
- `停止`：无模型时静默伪造“已转写”、本机失败自动上云、把实时预览覆盖成最终原文。
- `顺序`：R0 录音文件有效性 -> 本规格闭环 -> M2-08 WhisperKit/模型包 -> R2 素材库收口。
