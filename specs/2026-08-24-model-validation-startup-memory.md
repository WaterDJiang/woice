# 模型校验启动内存规格

## 目标

修复安装 Large-v3 后 Woice 启动阶段内存异常升高、可能被 macOS 内存压力终止的问题，同时保留模型逐文件 SHA-256 的 fail-closed 校验。

## 范围

- 将 App 内所有大文件 SHA-256 读取统一为固定大小缓冲区，单次读取默认不超过 1 MiB。
- WhisperKit 默认 Provider 选择和模型库存刷新仍验证文件大小、路径、符号链接与 SHA-256，不以缓存或弱校验替代完整校验。
- 不改变当前模型选择、下载、转写路由、原始录音、数据库、Keychain 或 Catalog 信任语义。
- 不在本任务重构模型库存刷新时序；重复校验的性能优化另行评估。

## 验收标准

- AC-MEM-001：多分块文件的统一 SHA-256 结果与 CryptoKit 一次性摘要一致。
- AC-MEM-002：统一实现使用固定原始缓冲区读取，不在循环中创建 `Data` 分块；读取失败返回可追溯 POSIX 错误。
- AC-MEM-003：当前模型文件被篡改时仍不能成为 WhisperKit Provider，继续安全回退本机 Speech。
- AC-MEM-004：模型安装、下载、库存、媒体导入与 Agent Context Package 的现有 SHA-256 契约全部回归通过。
- AC-MEM-005：安装包使用现有 Large-v3 启动后保持存活且工作台可见；稳定后 RSS 不超过 400 MiB，诊断前基线约为 1.78 GiB。
- AC-MEM-006：修复和覆盖安装不修改 `~/Library/Application Support/Woice` 中的模型、录音、转录、设置和数据库内容。

## 影响面

- `Sources/WoiceApp/` 的文件哈希实现。
- 模型库存、WhisperKit Provider 发现、模型下载/安装、媒体导入和 Context Package 哈希回归测试。
- Core/Offline 包装与已安装 App 启动验收。
