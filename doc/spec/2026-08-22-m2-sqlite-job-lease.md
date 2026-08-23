# M2-03c SQLite 元数据与 Job/Lease 持久化

> 状态：基础实现完成；前台顺序确认队列已接入，后台守护调度与更严格恢复验收待后续

## 1. 目标

- 将录音索引和处理任务从仅 JSON 投影升级为 SQLite/WAL 真相源，保证崩溃、重启和并发写入后状态可恢复。
- 保留已有 `recordings.json` 和音频文件，不删除、不覆盖原始数据；首次启动完成可回滚的迁移。
- 让 Job 的状态、幂等键、尝试次数、Lease 和失败原因有可查询的持久记录。

## 2. 数据边界

- SQLite 文件：`~/Library/Application Support/Woice/woice.sqlite3`，数据库和临时 WAL 文件仅当前用户可读写。
- `recordings` 表保存 RecordingRecord 的稳定字段和兼容 payload；`processing_jobs` 表保存每个 `ProcessingTask` 的规范字段。
- API Key 仍只进入 Keychain；Settings JSON 和 SQLite payload 都不得包含密钥。
- 音频、CAF、Markdown 仍由文件系统保存；SQLite 只保存相对文件名和校验元数据，不把音频写入 BLOB。

## 3. 迁移与一致性

- schema 版本通过 `PRAGMA user_version` 管理；v1 开启 WAL、foreign_keys 和 busy_timeout。
- 若 SQLite 为空而旧 `recordings.json` 存在，先校验并导入，成功后保留 JSON 作为可回滚备份，不重复导入。
- 每次 Recording 与 Job 投影更新在一个 SQLite 事务中提交；事务失败不更新内存成功状态。
- 读取优先 SQLite；数据库不可用时报告稳定存储错误并只读回退旧 JSON，不静默覆盖或删除；任何写入仍 fail-closed。

## 4. Job/Lease 规则

- 状态沿用 `queued -> awaitingAuthorization -> running -> completed | failed | cancelled | interrupted`。
- `idempotency_key` 唯一；同一录音、任务类型和配置快照不能创建重复 Job。
- `running` Job 写入 `lease_owner`、`lease_expires_at`；启动时过期 Lease 转为 `interrupted`，不自动外发。
- 外部 ASR/LLM 处理期间以不超过 20 秒的心跳续租；请求结束、失败或取消后立即停止心跳并释放 Lease，避免长请求被其他会话抢占。
- 用户重试显式创建新 attempt 或复用同一幂等 Job 的递增 attempt，原始音频和原始转录不变。

## 5. 验收标准

- 空数据库可创建、迁移并启用 WAL；重复初始化幂等。
- 旧 `recordings.json` 可一次性导入，导入前后 RecordingRecord 编解码等价，API Key 不进入 SQLite。
- Job 状态和 Lease 在进程重启后可恢复；过期 running Job 被标为 interrupted，未过期 Lease 不被其他 owner 抢占。
- 一个超过 60 秒的处理任务在心跳续租后仍保持同一 Lease，另一个 owner 不能抢占。
- 事务失败不会让 UI 显示未提交的完成状态；数据库错误有稳定 `WoiceError.storageFailure`。
- 单元/集成测试覆盖迁移、唯一幂等键、Lease 获取/续租/过期恢复、旧 JSON 兼容和文件路径安全；`make verify` 通过。

## 6. 非目标

- 本工作包不引入 GRDB 依赖、不迁移音频 BLOB、不实现后台守护进程。
- 不改变用户确认外发策略，不自动启动录音或自动发送云端请求。
