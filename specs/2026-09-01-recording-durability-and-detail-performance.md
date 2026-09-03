# 录音耐久与素材详情性能实施规格

## 变更记录（2026-09-01：故障保留语义）

- 录音停止时，如果最终音频容器不可读或 SQLite Recording 事务失败，但滚动 Manifest 中仍有已提交块，必须保留 Session Journal、Manifest 和块文件，交给下次启动恢复；不得走“失败即清理”的普通取消路径。
- 仅当没有任何可恢复块且没有可用音轨时，才清理空会话；保留路径必须释放当前内存对象但不删除磁盘上的恢复材料。
- 数据库事务失败必须回滚 Recording、Job 和摘要投影，不能留下半条素材或半个任务；既有音频文件与 Manifest 不受影响。
- 双轨会话只有一轨有效时，只恢复有效音轨和对应来源语义，不伪造缺失音轨或会议合成。
- 素材摘要正在异步补全时，录音与导入入口必须禁用或 fail-closed；不得用尚未 hydrate 的空内存集合重写 SQLite 素材库。
- 素材详情 hydrate 失败后也必须继续 fail-closed：不能仅清除 loading 标记就重新开放录音/导入、重命名、删除或转写；界面要保留摘要列表、显示可诊断原因，并提供显式重试 hydrate 入口。所有会改写完整 `recordings` 集合的入口（包括切换原文版本、重试处理和外发任务状态）都必须走同一 mutation gate，避免只加载一条详情后覆盖其他素材。只有完整详情成功载入后，素材变更入口才可恢复。

## 变更记录（2026-09-01：多声道麦克风 AAC 兼容）

- 真实设备回归中，麦克风 HAL 输出为 `3 声道 / 48 kHz / Float32 / interleaved`；AAC 设置依约束只创建 2 声道编码器，但旧实现直接写入 3 声道 buffer，`ExtAudioFileWrite` 稳定返回 `-50`。
- 主录音、VAD 段和滚动块必须共用同一次 PCM 规范化：保留原采样率，统一为 Float32 non-interleaved，输入超过 2 声道时先降混为 2 声道，再写入 AAC。不得在三个写入器中各自转换。
- 转换失败要在首帧门禁中立即失败并保留 Journal/Manifest；不能继续显示正在录音。
- 默认 `make test` 不得在已授权 Mac 上自动录制真实麦克风；只有显式设置 `WOICE_REQUIRE_MIC_AUDIO=1` 的麦克风验收入口才可运行真实录音测试。

## 目标

- 将录音从单个持续打开的容器提升为“滚动块 + 会话 Manifest + 最终合成”，保证已提交音频块可恢复。
- 让素材列表优先使用 SQLite 摘要投影，详情按 ID 异步加载并缓存，避免长原文阻塞列表和首屏。
- 建立可重复的 500 条素材、长音频和故障恢复基线，所有未达到真实 Mac 门禁的项保持待验收。

## 范围

- `RecordingChunkManifestStore`、`RollingPCMChunkWriter` 和恢复重建路径。
- `RecordingSessionJournal` 与双轨录音的 Manifest 关联。
- SQLite `recording_summaries` 投影、关键元数据的 FULL 同步语义。
- `RecordingDetailLoader`、素材摘要列表和详情缓存失效。
- 固定测试夹具、性能指标和 `os_signpost` 观测点。

## 非目标

- 不改变录音模式、音源选择、模型选择或云端外发策略。
- 不覆盖原始音频、原始 Transcript Artifact 或历史任务。
- 不把自动化故障注入结果替代真实 Mac 的 SIGKILL、休眠、设备变化和突然断电验证。

## 验收标准

- 每个已关闭的 10 秒音频块先以 `.partial` 写入，校验 SHA-256 后原子变为 `.committed`，Manifest 同步记录块元数据。
- Manifest 摘要不匹配、缺块和孤立尾块进入隔离或失败状态，不静默删除；正常停止仅在 Recording 事务提交成功后清理。
- 最终容器/元数据失败时，已提交块与 Journal 保留到下次启动；数据库事务回滚后不留下 Recording、Job 或摘要半提交。
- SIGKILL 故障注入能恢复全部已提交块；未提交尾部损失上限明确为不超过 10 秒。真实 Mac 验收结果必须单独写入日志。
- 固定 `3 声道 / 48 kHz / Float32 / interleaved` Fixture 经规范化后为 2 声道 non-interleaved，可同时写入主 M4A 和滚动 M4A 块；首帧不得出现 `AVFAudio error -50`。
- 500 条列表查询不解码完整 `payload_json`；详情读取可取消、按 ID 缓存最近 5 条，旧请求不能覆盖当前选择。
- SQLite 关键元数据连接使用 `synchronous=FULL`，旧 schema 可升级且原始音频/Artifact 数量不变。
- `make test`、`make lint`、`make docs-check`、`make harness-check`、`make verify` 通过；未运行的真实 Mac 或发行门禁不得标记为已完成。

## 影响面与回滚

- 影响录音写入、启动恢复、SQLite schema 和素材列表查询。
- 保留旧 Journal 与完整文件读取作为兼容回退；块级恢复失败时隔离临时块并保留原文件。
- schema 只增表/索引，不删除 `payload_json`；迁移前备份可用于回滚。
