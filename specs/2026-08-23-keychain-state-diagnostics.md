# Keychain 状态诊断

## 目标

当模型与转写设置确实修改 API Key 并触发 macOS Keychain 写入时，把 Security 返回的锁定、授权拒绝和用户取消转换为可执行的中文错误；普通设置保存仍不得读取或写入 Keychain。

## 范围

- `KeychainStore.write` 的 Security 状态映射。
- 设置保存失败反馈与本次提交的回滚语义。
- 不改变 Keychain account、服务名、密钥存储位置或外发确认。

## 不在范围

- 不自动解锁 login Keychain。
- 不保存密码、授权令牌或 Security 状态到日志、配置、SQLite 或 Artifact。
- 不绕过用户授权，也不把测试替身当作真实 Keychain 验收。

## 验收标准

- KC-001：`errSecInteractionNotAllowed` / `errSecNotAvailable` 明确提示解锁“钥匙串访问”后重试。
- KC-002：`errSecAuthFailed` / `errSecMissingEntitlement` 明确提示检查 Woice 的钥匙串授权或重新安装签名包。
- KC-003：`errSecUserCanceled` 明确提示本次设置未保存。
- KC-004：未知状态保留脱敏的数字状态码，不包含密钥或完整请求内容。
- KC-005：Keychain 写入失败时设置和草稿提交语义不变；录音、文件分区保存仍零 Keychain 访问。
- KC-006：新增状态映射纯测试通过；真实锁定/授权状态仍需在用户钥匙串可控的 Mac 上复验。

## 设计决策

Security 状态只在 Keychain 边界转换为稳定用户文案；`AppState` 继续把错误作为保存失败处理，并回滚本次已经写入的账号。读取接口保持兼容的空值语义，避免在启动时因钥匙串暂时锁定而伪造已有密钥。
