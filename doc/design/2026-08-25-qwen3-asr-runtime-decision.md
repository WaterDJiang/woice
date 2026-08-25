# Qwen3-ASR 本机 Runtime 许可证与接入决策

> 状态：Apache-2.0 已获用户确认；Runtime、模型包与 Store 打包门禁已验证；v0.1.3 GitHub Offline 作为 Qwen 预览包，正式性能矩阵与 Catalog 仍待收口
> 日期：2026-08-25
> 关联：[本机模型一键安装与 App Store 兼容规格](../../specs/2026-08-25-one-click-model-installation-and-store-compatibility.md)

## 结论

- 官方权重目标固定为 `Qwen/Qwen3-ASR-0.6B-hf@7f1569a48a89f3e3f4dc3a5c9d28bddd903bc76c`；权重许可证为 Apache-2.0。
- 原生 Swift/MLX Runtime 固定为 `vfasky/qwen3-asr-swift@4824c95e1e4624200405d639fb4ebe10f93f1075`，许可证为 Apache-2.0；它作为随 App 签名的 in-process 代码进入 Core/Store，共用同一个 `Qwen3ASRTranscriptionService`，不能通过 Python、Transformers、Shell 或外部端口运行。
- Apple Silicon 派生模型固定为 `mlx-community/Qwen3-ASR-0.6B-4bit@313d850181767edf09f00a9c289becca70e58cd0`，派生 Runtime 需要其 MLX-compatible Safetensors 格式。
- 模型下载包只包含权重、Tokenizer、配置、许可证与 Notice 数据；Runtime 代码不从下载包加载。
- 当前代码已经注册 `com.woice.qwen3-asr` 的 Runtime admission；实际模型文件已按固定 SHA-256 下载并通过原生加载冒烟，Qwen 仍在正式 Catalog 中保持 fail-closed，直到长文件/双轨性能矩阵与签名 Catalog 条目完成。
- Runtime 代码随 App 签名进入 Core/Store；MLX 的 `default.metallib` 由 Xcode Release 配置构建并随 `mlx-swift_Cmlx.bundle` 打包，SwiftPM 命令行不承担 Metal shader 编译。

## 已确认的依赖边界

用户已明确允许引入 Apache-2.0 的原生 Swift/MLX Runtime。本次接入固定以下边界：

- `vfasky/qwen3-asr-swift@4824c95e1e4624200405d639fb4ebe10f93f1075` 与 `mlx-swift@0.31.6` 及传递依赖写入 `Package.swift`、`Package.resolved`、`Resources/NOTICES.md` 和 `Resources/SBOM.json`。
- Runtime 只作为随 App 签名的 in-process Swift/MLX 代码使用；不下载或加载 Python、脚本、动态库、Swift bundle 或任意外部进程。
- 项目仍以 macOS 14 为最低平台；若上游未来提高平台要求，必须先重新评估而不是静默放宽或降级。
- 固定音频准确率、长文件、峰值内存、启动时间和签名 Catalog 仍是 Qwen 正式推荐/发布前的剩余门禁。

## 失败边界

- 未通过准确率、内存、长文件或签名 Catalog 门禁时，Qwen 不进入正式推荐和发布清单；WhisperKit/Speech 路径不受影响。
- 不把 Qwen 模型下载成功写成“可用”事实，除非对应 Runtime 已创建 Provider 并完成模型包原子提交。

## 用户确认

用户已明确允许采用 Apache-2.0 的原生 Swift/MLX Runtime。已完成：精确依赖锁定、模型包文件大小/SHA-256、来源与派生链、发行包 Notice/SBOM、真实模型加载与非空转写冒烟、Core/Store Xcode 构建及 Bundle 门禁。仍需完成：固定音频准确率、300 秒/长会议性能与内存矩阵、签名 Catalog 条目和真实录音手测。
