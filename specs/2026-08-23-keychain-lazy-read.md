# Keychain 延迟读取与设置分区隔离

## 目标

Woice 启动、录音与文件设置保存不读取 API Key；只有用户进入“模型与转写”、明确保存密钥或准备发送外部请求时，才读取对应 Keychain account。

## 范围

- `AppState` 启动时不主动读取 ASR/LLM Keychain。
- “模型与转写”分区打开时加载已保存密钥到当前设置草稿。
- 外部 ASR/LLM 请求建立前确保已加载对应密钥。
- 保持 Keychain account、密钥不落盘和独立保存语义。

## 不在范围

- 不绕过 macOS Keychain 授权。
- 不把密钥复制到日志、SQLite、Artifact、任务快照或子进程环境。
- 不自动解锁 login Keychain。

## 验收标准

- KC-LR-001：AppState 初始化不读取 Keychain。
- KC-LR-002：保存录音或文件分区不读取、不写入 Keychain。
- KC-LR-003：进入模型与转写分区后，已保存密钥只加载一次并显示为当前草稿值。
- KC-LR-004：外部 ASR/Markdown 请求建立前会加载对应密钥；本机 Provider 不触碰 Keychain。
- KC-LR-005：已有未提交的内存密钥不会被延迟加载覆盖。
- KC-LR-006：Keychain 仍不可写时，设置保存失败并保留原有回滚与可执行错误文案。

## 设计决策

`AppState` 维护一次性读取标记；延迟加载只填充空的已提交密钥，避免覆盖用户已经明确写入的运行时值。设置页在进入“模型与转写”时把已提交密钥合并到该分区草稿，其他分区草稿和保存路径不受影响。
