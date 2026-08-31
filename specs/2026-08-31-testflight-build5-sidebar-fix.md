# TestFlight 0.1.4 Build 5 侧栏修复发布规格

> 状态：已上传，等待 App Store Connect 处理  
> 日期：2026-08-31

## 目标

- 将工作台侧栏修复后的当前源码发布为 `0.1.4 (Build 5)`。
- 生成 `Woice.app` / `com.water.woice` / Store Channel 的无模型归档并上传 App Store Connect TestFlight。

## 范围

- 包含当前工作区已经验证的模型推荐、Dev/Store 隔离、旧 App 清理和侧栏恢复修改。
- 不上传本地 `Woice (Dev).app`，不携带模型权重，不读取或修改正式用户数据。
- 既有 Catalog 私钥缺失时不生成新信任根；Store 只使用已签名且可验证的线上 Catalog。
- 上传成功只表示 App Store Connect 接收构建，不表示 Apple 已完成处理、TestFlight 已可安装或 App Store 已发布。

## 验收标准

- `Resources/Info.plist` 与 `Resources/DistributionManifest.json` 均为 `0.1.4 (Build 5)`。
- `make verify`、Store Bundle 无模型门禁、Archive 身份和 Entitlements 检查通过。
- Archive 中 App 为 `Woice` / `com.water.woice` / `WOICEAppChannel=store`，且不存在模型目录。
- `xcodebuild -exportArchive` 的上传日志明确返回 `Upload succeeded`。
- 保留本地 Dev App、用户数据和当前上传 Archive；清理可重建的旧 App 残留。

## 结果

- 完整 `make verify` 通过：Swift 237 项、PI 7 项、MCP 2 项。
- Build 5 Store Archive 与导出包生成成功；版本、Bundle ID、Store Channel、双架构和无模型目录检查通过。
- Xcode 上传日志返回 `Upload succeeded`、`Uploaded Woice-Store`，Apple 当前状态为 `Uploaded package is processing`。
- 本机 `pkgutil` 仍把现有 Installer 证书链报告为不受信；Apple 上传前分析未因此拒绝包。TestFlight 可安装状态仍以 App Store Connect 完成处理为准。
