# 签名模型清单与 TestFlight 构建

## 目标

为 Store/TestFlight 构建提供可验证的 WhisperKit Tiny 与 Large-v3 模型清单，使用户能够在设置页显式刷新清单并点击下载；构建版本保持 `0.1.3`，Build 号递增并上传到 App Store Connect TestFlight。

## 范围

- 生成生产 `ModelCatalog` JSON：固定 `catalogID`、递增 `catalogVersion`、Tiny/Large-v3 清单、HTTPS 下载根地址和 Ed25519 签名。
- 将签名私钥、公钥信任根和上传凭据保留在本机未跟踪存储；仓库只保留可公开的 Catalog 元数据、签名公钥或示例，不提交私钥。
- 为 Store Archive 注入 `WOICEModelCatalogURL`、`WOICEModelCatalogID`、`WOICEModelCatalogTrustedKeys` 及 Catalog/模型下载 host allowlist。
- 递增 `CFBundleVersion`，生成签名 Store Archive，执行验证并上传到 App Store Connect TestFlight。
- 不在 Store/TestFlight 首次开放 Qwen3-ASR；继续遵守签名清单、Runtime、性能和审核门禁。

## 不在范围

- 不改变 App Store 版本号 `0.1.3`。
- 不把证书、私钥、API Key、Provisioning Profile 或模型权重提交到 Git。
- 不在未确认模型文件可公开托管、SHA-256 与下载地址有效前声明“可下载”。

## 验收标准

- Catalog 可由 `ModelCatalogVerifier` 使用构建内置公钥验签；篡改、回退和不受信 key 均拒绝。
- Catalog 中 Tiny/Large-v3 条目与本机固定 revision、文件大小、SHA-256、来源和 Store Runtime 元数据一致。
- Store Archive 的 `Info.plist` 含完整 Catalog 配置，`codesign --verify --deep --strict` 和 App Store Bundle 门禁通过。
- App Store Connect 接收新 Build，TestFlight 页面可见版本 `0.1.3` 的新 Build；上传结果以 App Store Connect 页面/Transporter 成功状态为准。
- 未满足签名身份、Catalog 托管或上传认证任一前置条件时 fail-closed，并记录原始错误。

## 外部依赖与停止点

- Apple Distribution 证书、`com.water.woice` 对应的 App Store provisioning profile 和 App Store Connect 上传认证必须在本机可用。
- Catalog 及模型包必须有稳定 HTTPS 托管；模型权重再分发许可、公开下载带宽和 URL 需要确认。
- 上传是外部状态变更，仅在本规格门禁和本机验证通过后执行；若凭据缺失，停止在本地 Archive/诊断，不伪造上传成功。
