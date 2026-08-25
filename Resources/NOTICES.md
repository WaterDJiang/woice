# Woice Notices

本文件只记录随当前产物声明的第三方来源。发行 App 的 `Contents/Resources/ThirdParty/` 包含依赖仓库的许可证文本；模型包保留上游 `README.md` 作为可读 Notice，来源与摘要同时写入 `manifest.json` 和 SBOM。

## Argmax OSS Swift / WhisperKit

- 版本：`argmax-oss-swift` `1.0.0`
- 来源：https://github.com/argmaxinc/argmax-oss-swift
- 许可证：以仓库发布的许可证文件为准；构建门禁固定精确版本，不使用浮动依赖。

## Qwen3-ASR Native Runtime

- `vfasky/qwen3-asr-swift`，固定提交 `4824c95e1e4624200405d639fb4ebe10f93f1075`，Apache-2.0。
- 仅使用 `Qwen3ASR` 与 `Qwen3Common` library products；Qwen TTS、CLI 和 IME 不进入 Woice。
- `mlx-swift` `0.31.6`，固定提交 `0bb916c67f4b9e5c682cbe02a42c701c93ab5021`，MIT。
- 其传递依赖按 `Package.resolved` 固定并记录在 `SBOM.json`；发行包的 `ThirdParty/` 目录保留 Apache-2.0/MIT 等依赖的完整许可证文本。

## Qwen3-ASR 0.6B Model Pack

- 派生模型：`mlx-community/Qwen3-ASR-0.6B-4bit`，固定 revision `313d850181767edf09f00a9c289becca70e58cd0`，Apache-2.0。
- 上游模型：`Qwen/Qwen3-ASR-0.6B-hf`，固定 revision `7f1569a48a89f3e3f4dc3a5c9d28bddd903bc76c`；上游权重 SHA-256 和 MLX 转换链记录在模型包 `manifest.json`。
- 派生格式：MLX safetensors 4-bit；转换工具 `mlx-audio` `0.3.1`。
- 模型包内保留上游 `README.md` 作为可读 Notice；本文件与发行包 `ThirdParty/` 共同承担发行包级 Apache-2.0 来源指针。

## WhisperKit 模型包

- 来源和 revision 记录在每个模型包的 `manifest.json` 与 `NOTICE.txt`。
- 未通过文件 SHA-256、路径、符号链接和许可证信息校验的模型不会进入安装事实或 Offline 产物。
