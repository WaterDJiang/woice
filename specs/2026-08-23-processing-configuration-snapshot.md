# ProcessingTask 配置快照规格

> 状态：代码与自动测试完成；跨版本真实数据迁移和发行验收待完成
> 日期：2026-08-23
> 替代：无；补齐 M2-08a 的 Job 配置快照缺口
> 保留：`ProcessingTask` 现有 Provider、模型、版本、位置、能力和幂等键字段；旧任务缺失哈希时继续可读
> 迁移：新建或重试的任务写入 `configurationHash`；历史任务不强制回填，不修改既有 Artifact
> 停止：哈希中不得包含 API Key、完整授权头、原始音频、原文或未脱敏 URL 凭据
> 顺序：配置规范化 -> SHA-256 摘要 -> 写入任务快照 -> 重试时按当次实际配置更新

## 目标

- 让每条 ASR/LLM Job 能证明当次使用的非机密配置，而不是只记录可变的当前设置。
- 模型切换、Endpoint/模型修改或语言/时间戳参数变化后，重试任务生成新的可辨识快照。
- API Key 继续只存在 Keychain 和运行时请求中，不进入任务、日志、sidecar、数据库或导出。

## 规范化字段

摘要输入固定包含：任务类型、Provider ID、模型 ID、模型版本、数据位置、能力、Endpoint 的 scheme/host/port/path（省略 user/password/query/fragment）、语言、时间戳参数、音轨和会议模式。

摘要输出为小写 SHA-256 十六进制字符串，前缀固定 `sha256-v1:`。同一字段集合和顺序必须得到相同摘要；任一有效配置字段变化必须得到不同摘要。

等待选择模型的任务没有实际 Provider 配置，`configurationHash` 可以为空；历史 JSON 缺失该字段按 `nil` 兼容读取。

## 验收标准

- 新建本机、外部和重试任务均持久化 `configurationHash`。
- 相同配置重复保存摘要相同；模型版本、Endpoint 路径、语言、时间戳或音轨变化会改变摘要。
- API Key 改变不会改变摘要，摘要和导出的任务 JSON 中不出现 Key 明文。
- 旧任务 JSON 仍可读取，缺失哈希不阻塞重试；重试成功后写入新摘要。
- `make test`、`make verify`、`make docs-check`、`make harness-check` 通过。
