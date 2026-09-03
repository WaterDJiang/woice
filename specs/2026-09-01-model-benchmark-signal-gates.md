# 模型基准的空信号与严格门禁规格

## 目标

- 让模型基准准确表达产品的 `fail-closed` 语义：静音或纯噪声没有可读语音时，应保留原始音频并返回空结果，不应被误报为模型运行失败。
- 继续拦截模型在静音/噪声上产生非空幻觉、语音样本空输出、模型加载错误、协议污染和输出质量错误。
- 报告中明确区分“预期无文字”和“异常失败”，不通过放宽门禁掩盖模型质量问题。

## 范围

- `Tests/WoiceAppTests/ModelBenchmarkTests.swift` 的严格基准判定和报告字段。
- Qwen Provider 对无文字 chunk 的处理：无文字 chunk 是长音频中的合法 no-op，整段没有文字时仍以 `emptyResult` fail-closed。
- 仅影响基准诊断和本机 Provider 的错误分类，不改变原始音频、Transcript Artifact 或云端外发策略。

## 判定规则

- `zh`、`en`、`mixed` 等语音类别：必须返回非空、无错误；若有参考文本，继续记录 WER，但不把没有可信参考的样本伪造成准确率结论。
- `silence`、`noise` 类别：必须没有可读文字；以明确的 `emptyResult` 失败表示预期结果。返回非空文字、模型加载错误、音频错误或其他异常均失败。
- 静音/噪声类别不得因为 `outputIsEmpty` 就自动通过；只有错误语义明确为“没有识别出文字”时才算预期空结果。
- Qwen 长音频中的单个空 chunk 不应丢弃此前已提交的文字；所有 chunk 均为空时仍不创建 ready Transcript Artifact。
- 任何 `QwenOutputParserError.qualityRejected`、替换字符、byte 残留或协议污染继续失败关闭。

## 非目标

- 不把当前 Qwen 合成中文 WER 结果升级为正式准确率结论。
- 不把 WhisperKit 在静音/噪声上的非空输出改写成通过；它仍应在多模型严格矩阵中暴露为质量问题。
- 不解锁 Qwen 正式 Model Catalog 推荐；完整中文/中英混合/长时质量、上游 Runtime 对照和签名 Catalog 仍按活动计划处理。

## 验收

- Qwen-only 严格基准：语音类别通过，静音/噪声以预期空结果通过，RTF 与内存阈值仍生效。
- Qwen-only 基准必须有独立、可重复的入口：`make model-benchmark-qwen-only-strict WOICE_BENCHMARK_AUDIO_DIR=<fixture-dir> WOICE_BENCHMARK_OUTPUT=<report.json>` 只选择固定 Qwen pack，不隐式把其他已安装 Provider 混入。
- 官方对照样本必须通过固定 HTTPS 地址和预期 SHA-256 获取到隔离目录；下载失败或摘要不匹配时 fail-closed，不把临时/未知音频当作官方参考。
- WhisperKit + Qwen 多模型严格基准：若任一 Provider 在静音/噪声返回非空，门禁失败并在报告中保留对应样本。
- 单元测试覆盖预期空结果、非空幻觉、模型/音频异常和语音类别空输出四条路径。
- `make test`、`make verify`、`make docs-check`、`make harness-check` 与 `git diff --check` 通过。

## 当前自动证据（2026-09-01）

- Qwen-only 五类各 300 秒严格基准通过：最大 RTF `0.0626`，峰值 RSS `893,648,896` bytes；静音/噪声均为 `empty_result`，语音类别非空。
- 使用现有公开 30 秒夹具循环生成的五类各 3600 秒隔离输入，Qwen-only 长时执行通过：最大 RTF `0.0606`，峰值 RSS `898,056,192` bytes，报告为 `build/model-benchmark-qwen-only-strict-60m-20260901.json`。
- 60 分钟输入是重复夹具的稳定性/资源压力证据，不代表真实会议内容准确率；由于循环夹具没有可信逐字参考，WER 保持为空。真实中文/混合语音质量、重复率与目标 Mac 长时 UI 仍按活动计划待人工/外部验收。
- 官方 Qwen 中英文参考夹具来自 Qwen 官方示例中的固定音频 URL 和逐字文本；下载目录只在 `/private/tmp` 使用，文件 SHA-256 分别为英文 `f9b4440ac8393e47c14a6240e9739dea09b645bb1592b8f2dd48feb9666cea7f`、中文 `46dbc998c9d1d48111267c40741dd3200f2e5bcf4075f8c4c97f4451160dce50`。
- 固定 Qwen pack 的官方参考对照通过：中文 WER `0`、英文 WER `0.0263`，均非空且无错误；报告为 `build/model-benchmark-qwen-only-official-reference-20260901.json`。这只覆盖官方短样本，不代表混合语音、静音/噪声或真实会议完整准入。
- 新增 Make 入口已实际复跑：`make model-benchmark-qwen-official-reference WOICE_BENCHMARK_AUDIO_DIR=<隔离目录> WOICE_BENCHMARK_OUTPUT=<报告>` 完成下载、Store 依赖构建和固定 Qwen pack 对照；最新报告为 `build/model-benchmark-qwen-only-official-reference-from-make-20260901.json`。
