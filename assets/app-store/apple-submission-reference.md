# Woice Apple 上架资料参考快照

> 快照日期：2026-08-24
> 用途：MAS-00 本机准备；不替代 Apple Developer Program、App Store Connect 后台和法律主体的最终判断。

## 官方资料

- [App Store Connect 截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
  - macOS 应用必须提供截图。
  - 可用尺寸为 16:10 的 `1280×800`、`1440×900`、`2560×1600` 或 `2880×1800`。
  - 单个本地化可上传 1～10 张 `.jpeg`、`.jpg` 或 `.png`，不得带 alpha/透明通道。
- [上传 App 构建版本](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
  - 可用 Xcode、Transporter、altool 或 App Store Connect API 上传。
  - App Store Connect 用 Bundle ID、版本号和 Build 字符串关联构建；上传后还要等待 Apple 处理。
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
  - `PrivacyInfo.xcprivacy` 必须作为 Target 资源进入 Bundle，并描述数据收集和适用的 Required Reason API。
- [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
  - 使用覆盖范围内的 Required Reason API 时，必须在对应隐私清单声明获批准的理由；不能用空清单掩盖实际 SDK/API 使用。
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
  - 提交前必须保证应用可运行、元数据完整、审核路径可用，并在 Review Notes 解释不明显的能力。
  - macOS 应用应使用合适的沙盒/API，不能通过应用外安装器、后台自更新或下载额外代码改变审核时的产品能力。

## 当前本机事实

- 已完成：`project.yml` → `Woice.xcodeproj`、`Woice-Store` Scheme、无签名 Store 构建、AppIcon、PrivacyInfo、NOTICES、DistributionManifest 和 SBOM 资源门禁。
- 已完成：Store 能力裁剪和本机 ad hoc Bundle 静态预检；不注册外部 Agent、Unix Socket、Process Provider、自动粘贴或自有更新器。
- 未完成：Apple 开发者团队、签名身份、Provisioning Profile、正式 Archive/Validate、上传、TestFlight、线上隐私政策 URL、最终截图和审核提交。
- 未决定：开发者主体、最终 SKU/价格/地区、首版默认模型、模型权重再分发许可、是否在首版保留自动粘贴。

## 提交前动作顺序

1. 冻结 MAS-00 产品/账号决策和模型许可证结论。
2. 用最终签名身份执行 `make archive-app-store`，并由 Xcode Organizer Validate。
3. 从待提交 Build 采集 16:10、无透明通道的真实 macOS 截图。
4. 完成线上隐私政策、App Privacy、出口合规、Review Notes 和支持 URL。
5. 上传唯一 Build，等待 App Store Connect 处理，再进入 TestFlight 和审核。
