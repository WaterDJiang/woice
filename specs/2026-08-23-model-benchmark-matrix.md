# M2-08i 模型基准矩阵执行规格

## 目标

把“模型基准已生成”与“默认模型可冻结”区分开。基准入口必须能够证明每个模型在中文、英文、混合、静音和噪声样本上的转写结果、RTF、峰值内存和失败状态。

## 输入契约

- 音频文件名以 `zh-`、`en-`、`mixed-`、`silence-` 或 `noise-` 开头；同目录可放置同名 `.txt` 参考文本。
- 基准目录和模型库存由调用方显式指定；测试不下载模型、不扫描公网、不读取用户录音目录。
- 默认报告允许短样本用于开发调试；只有设置 `WOICE_ENFORCE_MODEL_BENCHMARK=1` 时才启用完整矩阵门禁。
- 完整矩阵门禁要求五类样本均存在，单个样本时长不少于 `WOICE_BENCHMARK_MIN_DURATION_SECONDS`（默认 300 秒），且报告没有失败/空输出。

## 验收

- 报告保存每个模型/样本的 category、音频时长、elapsed、RTF、峰值常驻内存、空输出、可选 WER 和错误。
- 完整门禁额外检查五类覆盖、最短样本时长、RTF ≤ 1.0、峰值内存 ≤ 4 GiB。
- 缺类、短样本、失败或空输出时测试失败，并且不会写入“默认模型已冻结”的成功结论。
- 执行入口：开发调试使用 `make model-benchmark`；发布门禁使用 `WOICE_BENCHMARK_AUDIO_DIR=/path/to/benchmark make model-benchmark-strict`。
