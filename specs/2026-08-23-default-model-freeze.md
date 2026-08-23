# WhisperKit 默认模型冻结规格

> 日期：2026-08-23  
> 状态：基于本机严格性能门禁冻结候选  
> 关联：[模型接入与双版本发布计划](../doc/plan/2026-08-22-model-integration.md) · [模型基准矩阵](2026-08-23-model-benchmark-matrix.md) · [基准 Fixture 生成器](2026-08-23-model-benchmark-fixture-generator.md)

## 决策

将已安装且未被用户显式选择时的 WhisperKit 默认本机模型固定为 `com.woice.whisperkit.large-v3`，版本为 `0f63a7800b00dd0226abd051b906c246e1907482`，模型标识为 `openai-whisper-large-v3-v20240930-626mb`。

如果默认 Large-v3 不存在、损坏或校验不通过，按已验证的安全回退顺序选择 Tiny，再回退到 macOS on-device Speech；不会静默下载、切换到云端或覆盖用户已保存的模型选择。

## 证据

- Tiny 与 Large-v3 均通过五类各 300 秒严格矩阵：中文、英文、混合、静音、噪声。
- Tiny：最高 RTF 0.041，峰值常驻内存约 934.5 MiB，五类均非空且无错误。
- Large-v3：最高 RTF 0.267，峰值常驻内存约 1,207.4 MiB，五类均非空且无错误。
- 两者均满足 RTF ≤ 1.0、峰值内存 ≤ 4 GiB；本次性能样本为本机系统语音生成的可复现 Fixture，不替代真实用户会议准确率验收。

## 兼容裁决

- 替代：替代“按目录字典序或未来新增模型偶然决定默认值”的隐式路由。
- 保留：用户在设置中选择的模型包/版本优先级、损坏模型 fail-closed、Tiny 作为低资源替代和 macOS Speech 兜底。
- 迁移：旧设置中 `selectedLocalModelPackID` 为空表示“跟随默认”；已有非空选择不迁移、不覆盖。
- 停止：停止因模型下载完成而自动改变用户当前选择，停止把性能报告当作用户显式切换事实。
- 顺序：启动解析用户选择 -> 已验证默认 Large-v3 -> 已验证 Tiny -> on-device Speech；每一步都只使用通过完整文件校验的模型。

## 验收标准

- 新增启动路由测试，证明两套已安装模型同时存在时默认 Large-v3。
- 用户选择 Tiny 后重启仍使用 Tiny；Large-v3 缺失或校验失败时回退 Tiny/Speech。
- 设置页明确显示“默认模型：Large-v3（可手动切换）”，不再写“等待基准后成为默认”。
- 旧设置 JSON、无模型 Core 和 Offline 单模型包保持兼容。
