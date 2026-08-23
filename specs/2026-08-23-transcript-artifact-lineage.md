# 转写 Artifact 版本链规格

## 目标

确保录音重转写、来源分离转写和模型切换不会丢失旧原文。当前详情页可以继续展示一个“当前原文”投影，但每次完成的转写都必须作为不可变版本留存，并能追溯使用的模型和任务。

## 数据契约

- `TranscriptArtifact.id` 是转写版本稳定 ID，`parentRecordingID` 指向所属录音，`supersedesID` 指向上一版转写。
- Artifact 保存规范化文本、时间戳片段、来源音轨/会议模式、Provider、模型、模型版本、数据位置和配置摘要；不得保存 API Key 或完整 Endpoint。
- `RecordingRecord.transcript` 和 `transcriptSegments` 只是当前显示投影；新的转写不能删除 `transcriptArtifacts` 中的旧版本。
- 旧数据没有版本数组时，第一次重转写前先把已有原文作为兼容 Artifact 保存，再追加新版本。
- 选择历史版本只改变当前投影和 active ID，不修改任何 Artifact 内容或原始音频。

## 范围

- 本机、外部、会议来源分离和标准 meetingMix 转写成功路径统一写入版本链。
- 详情页在存在多个版本时显示版本列表、模型快照和当前版本，并允许切换当前投影。
- 导出时间戳 JSON 包含版本 ID、父子关系和处理快照，保持已有字段兼容。

## 不在范围

- 不允许人工覆盖原始 Artifact；编辑和 Agent 派生版本另由后续工作包承接。
- 不删除历史版本；删除录音时按现有可恢复删除策略处理整个录音树。

## 验收标准

- 首次转写产生一个 Artifact；模型切换重转写后至少有两个 Artifact，旧文本和新文本均可读取。
- `supersedesID` 形成单向链，原始音频 SHA-256 不变。
- 选择旧版本后当前详情显示旧文本，再次重转写仍以当前任务产生新版本，不覆盖历史。
- 导出的时间戳 JSON 能解码版本 ID、`parentRecordingID`、`supersedesID` 和模型版本；不包含 API Key/Endpoint。

## 替代、保留、迁移、停止、顺序

- 替代：替代重转写直接覆盖单一 `transcript` 字段的实现路径。
- 保留：现有 `RecordingRecord` 当前原文投影、Job/Lease、模型快照和旧 JSON 解码。
- 迁移：旧记录在首次重转写时懒迁移为一个兼容 Artifact，不批量改写用户文件。
- 停止：禁止新增任何原位覆盖原始转录的重试或模型切换路径。
- 顺序：属于 R2 素材库收口的 Artifact 来源链；在 M2-09 Agent 派发前完成。
