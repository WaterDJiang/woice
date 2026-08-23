# M2-08d 签名模型 Catalog 验证

## 目标

为远程模型清单建立可版本化、可审计的 Ed25519 签名契约。Catalog 验证失败时不得进入下载或安装流程。

## 契约

- Catalog 包含 schema、稳定 ID、生成时间、完整 `ModelPackManifest` 条目和签名。
- 签名算法固定为 `Ed25519`；签名值与公钥使用 Base64；`keyID` 用于轮换和审计。
- 签名覆盖去除 `signature` 字段后的排序 JSON，不覆盖网络 URL 或运行时状态。
- 条目 `packID` 不可重复；Catalog schema major 不支持时 fail-closed。

## 非目标

- 本任务不生成或内置生产私钥，不把测试 key 当成发布 key。
- 本任务不决定生产 Catalog host、公钥配置、定时更新策略、真实发行服务或 Developer ID/公证；传输、密钥轮换和条目下载契约见 `specs/2026-08-23-catalog-transport-and-key-rotation.md` 与 `specs/2026-08-23-catalog-model-download-orchestration.md`。

## 验收

- 正确 Ed25519 签名可验证；签名内容、keyID、算法、公钥或条目任一改变都会拒绝。
- 重复 packID、空条目、未知 schema 和非 Ed25519 算法 fail-closed。
- 验证器不产生网络请求、不写入模型库存。
