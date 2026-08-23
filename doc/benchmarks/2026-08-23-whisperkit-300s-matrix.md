# WhisperKit 五类 300 秒模型基准

## 执行事实

- Fixture：`make model-benchmark-fixture WOICE_BENCHMARK_AUDIO_DIR=/private/tmp/woice-model-benchmark-300-v2 WOICE_BENCHMARK_MIN_DURATION_SECONDS=300`
- 类别：`zh`、`en`、`mixed`、`silence`、`noise`；每类 300 秒，16 kHz、单声道、PCM WAV。
- 模型：Tiny 与 Large-v3 均使用固定 revision `0f63a7800b00dd0226abd051b906c246e1907482`。
- 运行：`make model-benchmark-strict`，未上传音频，输出为本机 `build/model-benchmark-*-300-v2.json`。

## 结果

| 模型 | 五类覆盖 | 最差 RTF | 峰值常驻内存 | 空输出/错误 |
|---|---:|---:|---:|---:|
| WhisperKit Tiny | 5/5 | 0.041 | 934.5 MiB | 0/0 |
| WhisperKit Large-v3 | 5/5 | 0.267 | 1,207.4 MiB | 0/0 |

两者均满足严格门槛：RTF ≤ 1.0、峰值内存 ≤ 4 GiB、五类样本均达到 300 秒且没有失败或空输出。Large-v3 在这套可复现系统语音样本上的 WER 为：英文 0.072、混合 0.411、中文 1.124；Tiny 分别为 0.071、0.810、2.727。

## 解释边界

这套 Fixture 用 macOS 系统语音生成，适合性能、长音频、静音/噪声和失败状态门禁，不等同于真实会议参与者的准确率或说话人分离验收。默认路由已冻结为 Large-v3；真实会议和人工语料仍需单独桌面 Journey。
