# 本机已完成任务重转写规格

## 目标

- 详情页点击“重新转写”时，即使原本机转写任务状态为 `completed`，也必须创建并执行一轮新的本机转写。
- 新结果追加为新的 Transcript Artifact；旧原文、旧 Artifact 和原始音频保持不变。
- 继续使用同一素材级 idempotency key，禁止同一素材并发启动两轮本机转写。

## 根因

- 本机路径复用已有 `ProcessingTask` 的 idempotency key 取得 SQLite Lease。
- `processing_jobs` 的 Lease 条件只允许 queued/waiting/running/failed/interrupted/cancelled，不包含 completed。
- 重转写前任务仍保持 completed，导致 Lease 获取失败，界面只留下“其他会话正在转写”的误导性状态。

## 规则

- 用户明确触发重转写时，已完成任务先回到 queued，再按既有 Lease、running、completed 流程执行。
- running 任务不重置；仍由 Lease 和活动任务去重保护。
- 失败、被中断或等待模型的任务继续使用既有重试语义。
- 不放宽 Runtime、模型路径、权限或外发策略；本规格只修正本机已完成任务的重入状态。

## 验收

- 已有 transcript + completed 本机任务点击重转写后，Provider 调用次数为 1，任务最终为 completed。
- 结果文本更新，Transcript Artifact 数量增加 1，旧 Artifact 文本和原始音频不变。
- 连续点击不会增加第二次 Provider 调用。
- `make test`、`make verify`、`make docs-check`、`make harness-check` 与 `git diff --check` 通过。

## 非目标

- 不改变外部 ASR 的授权确认流程。
- 不在本规格中执行真实桌面、TCC 或用户素材验收。
