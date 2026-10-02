# Woice 0.1.8 (13) Qwen 转写稳定性修复更新

## 简体中文更新说明

修复使用本机 Qwen 模型转写部分录音时，临近结束可能导致应用意外退出的问题。
改进音频分段与极短尾段处理，提高转写稳定性。

## 英文审核备注

This update fixes a crash when transcribing some recordings with the on-device Qwen model. It accumulates short audio reads and safely handles very short final audio segments. The fix does not add permissions, data collection, external transmission, dependencies, or model downloads. Original recordings and existing transcripts are preserved.

Validation included a synthetic 4 ms audio input and a complete 18-minute recording with the real on-device model. Both completed without a crash; the source recording SHA-256 remained unchanged. No private recording or transcript is included in the app bundle.
