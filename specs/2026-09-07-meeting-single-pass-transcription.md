# 会议合并音频单次转写修复规格

> 状态：已实施，自动验证通过；真实会议重叠说话效果待人工验收  
> 日期：2026-09-07  
> 关联：`doc/spec/2026-08-22-dual-track-meeting-transcription.md`、`specs/2026-08-24-reliable-dual-track-transcription.md`、`specs/2026-08-25-dual-source-storage-and-long-detail.md`  
> 覆盖：上述规格中“默认对麦克风和电脑声音分别转写”的产品默认值  
> 保留：双原轨不可覆盖、会议合并音频可重建、Transcript Artifact 版本链、显式分轨模式

## 1. 问题和根因

- 当前“完整会议（推荐）”为麦克风和系统音频各创建一个 ASR Job。
- 麦克风会回采扬声器中的电脑声音；同一句话因此同时进入两条音轨。
- 两轨结果目前只按时间排序合并，不做跨轨语义去重；Qwen 对两条输入的识别文字不完全相同，精确字符串去重无法解决。
- Markdown 只渲染一次当前 `record.transcript`；重复在转写合并阶段已经产生，不是 Markdown 重复执行。
- 2026-09-07 本机最新长会议元数据显示：8063 秒、两个转写 Job 均只尝试 1 次，激活结果由 269 个麦克风片段和 269 个系统音频片段组成。

## 2. 产品裁决

- 新安装和本次策略升级后默认使用 `standardMix`：保留两条原轨，生成 `meetingMix`，只对 `meetingMix` 执行一次 ASR。
- `sourceSeparated` 保留为用户显式选择的高级模式；界面必须明示“约两倍处理时间”和“外放可能重复”。
- 单次模式不承诺保留重叠说话的每一轨，也不保证消除原音频中的外放回声；这是“一条混音时间线转写”和“双轨分别转写/尽量保留重叠说话”的取舍。2026-09-08 新增外放回声方案见 `specs/2026-09-08-recording-controls-echo-and-workspace-polish.md`，状态为待实施。
- 旧的 Transcript Artifact 不修改、不删除。历史会议下次手动重转写时，使用当前设置的会议策略并追加新 Artifact。

## 3. 实施范围

- `AppSettings`：默认改为 `standardMix`，策略版本升为 2；版本 0/1 的旧默认迁移到单次模式，升级后用户再显式选择分轨可正常往返。
- 新录音：双轨原件提交后依然生成 `meetingMix`，但默认只创建 `meetingMix` 转写任务。
- 历史重转写：以当前设置为真相源重建转写任务；需要单次转写而合并文件缺失时，从两原轨重建，失败则 fail-closed。
- 异常恢复：两原轨有效且合并文件重建成功时，恢复记录标记为 `standardMix`。
- UI：调整模式名称、说明和详情页文案，不再把分轨冒充为无代价的默认推荐。

## 4. 验收标准

- `MSP-TAC-001`：新 `AppSettings` 默认为 `standardMix`，旧策略版本迁移一次，新版显式 `sourceSeparated` 可往返。
- `MSP-TAC-002`：麦克风和系统音频都有效时，默认只产生一个 `meetingMix` 转写 Job 和一次 Provider 调用。
- `MSP-TAC-003`：显式选择 `sourceSeparated` 时仍生成麦克风、系统音频两个 Job，两轨均保留 `sourceTrack`。
- `MSP-TAC-004`：历史分轨素材在当前设置为单次模式时重转写，任务收敛为一个 `meetingMix` Job；原音频字节和旧 Artifact 不变。
- `MSP-TAC-005`：合并文件缺失时可重建；重建失败时不改用麦克风单轨冒充会议转写。
- `MSP-TAC-006`：Markdown 导出只包含当前激活 Transcript 一次，不会把历史分轨 Artifact 追加到导出。
- `MSP-TAC-007`：`make test`、`make lint`、`make docs-check`、`make harness-check` 通过。

## 5. 影响面与回滚

- 影响 `AppSettings`、录音停止编排、手动重转写、异常恢复、设置文案和会议验收测试。
- 不变更原始音频文件、模型包、Provider 协议、Markdown 格式和数据库 schema。
- 若单次混音的重叠说话遗漏不可接受，用户可显式选择“分轨转写（高级）”；不回滚双原轨存储。

## 6. 实施结果

- 新建及旧策略设置默认迁移为 `standardMix`；策略 v2 仍可显式保存 `sourceSeparated`。
- 新录音和历史重转写默认只编排一个 `meetingMix` 任务；缺失的派生合并文件会先重建并持久化文件名。
- 旧 Transcript Artifact、麦克风原件和系统音频原件不修改；Markdown 仍只投影当前激活 Transcript。
- `make verify` 通过：281 项 Swift Testing、18 项 XCTest、7 项 PI、2 项 MCP，以及文档、Harness、lint、工程生成和 Dev Bundle 门禁；`make xcode-build-store` 的无签名双架构 Store Target 编译与 Bundle 验证也已通过。
