# 模型切换后的已有录音重转写

> 状态：已实现，Large 已安装 WAV 本机推理验收通过；性能基准与发布门禁另计
> 日期：2026-08-22

## 目标

用户下载并切换本机 Large 模型后，可以对已有录音发起一次新的本机转写。重转写必须使用当前选定模型快照，不覆盖原始音频或已有原文；短暂的同任务竞争不应直接显示为不可恢复的失败。

## 现象与根因假设

- 现象：已有录音点击“重新转写”后，处理任务失败，提示“这条本机转写任务正在其他 Woice 会话中运行，请稍后重试”。
- 已验证：SQLite `processing_jobs` 的幂等键为录音 ID + `transcription`；本机转写在抢不到 Lease 时立即写入 `failed`。
- 影响：模型切换后的首次重试可能与尚未结束的旧任务或重复点击短暂竞争，界面把可恢复的等待误呈现为最终失败。
- 仍需验证：Large-v3 包的 WhisperKit pipeline 是否可从已安装目录加载并完成一段本机 WAV 转写。

## 范围

- 保留一个录音对应一个转写幂等键和 Job Lease。
- 本机转写重试在 Lease 被其他会话持有时，短时间按退避等待；超时仍保留原始录音，并给出可执行提示。
- 任务元数据在开始尝试前刷新为当前 `providerID/modelID/modelVersion/dataLocation`，确保切换模型后新尝试的快照可见。
- 同一 AppState 对同一录音只允许一个本机转写任务在途，重复按钮动作不会并发启动第二个任务。
- 若 Large pipeline 加载失败，显示模型加载阶段和原因，不回退到云端、不删除已有原文。

## 不在范围

- 不自动把本机音频发送到外部 ASR。
- 不删除旧模型、旧原文或原始 WAV。
- 不把重转写改成后台批量队列；持久化批量补转写另立任务。

## 验收标准

- AC-MODEL-RETRY-001：切换到已安装 Large 后，已有录音点击“重新转写”，任务最终使用 Large 的 Provider、模型 ID 和版本快照。
- AC-MODEL-RETRY-002：同一录音重复点击重试，只有一个本机转写调用在途；不会把第二次点击误报成“其他会话失败”。
- AC-MODEL-RETRY-003：Lease 被短暂占用时，界面显示等待/重试语义；等待超时后任务可再次点击重试，原始音频和已有原文仍存在。
- AC-MODEL-RETRY-004：Large pipeline 加载失败时，任务失败原因包含本机模型加载失败，且不隐式切换到 Tiny、Speech 或外部 ASR。
- AC-MODEL-RETRY-005：原始录音 SHA-256 不变；已有原文只有在新转写成功后才创建新的转录结果。

## 验证计划

- Swift 单元测试：同一 AppState 的重复重试去重、Lease 短暂竞争等待、当前模型快照写入。
- 本机集成测试：使用已安装 Large manifest 对固定 WAV 完成 WhisperKit load/transcribe（显式环境变量门禁）。
- 回归门禁：`make docs-check && make harness-check && make verify && make acceptance-core`。

## 替代 / 保留 / 迁移 / 停止 / 顺序

- 替代：替代“抢不到 Lease 即立即失败”的本机重试行为。
- 保留：原始音频不可变、外部 ASR 首次外发确认、ProcessingTask 模型快照。
- 迁移：模型切换后的已有录音重转写统一经过当前本机 Provider 和同一幂等 Job。
- 停止：不再把短暂 Lease 竞争直接写成最终失败并要求用户猜测原因。
- 顺序：先完成 Lease/去重修复，再完成本机 Large pipeline 显式验收；不阻塞录音主链路。
