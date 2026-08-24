# Woice Store App Target 边界

这里记录正式 Xcode macOS App Target 的组合根边界。根目录 `Package.swift` 仍是核心开发与测试真相源；`project.yml` 是 Xcode 工程的唯一输入，使用本机 XcodeGen 2.46.0 生成 `Woice.xcodeproj`，禁止手工编辑生成的 pbxproj。

本机可用的工程检查命令：

```bash
make xcode-project
make xcode-list
make xcode-build-store
```

`xcode-build-store` 只验证 `Woice-Store / Release-AppStore` 的无签名编译、链接和 Bundle validation；它不代表 Apple 分发签名、Archive、TestFlight 或审核通过。

正式 Target 从 `assets/brand/exports/AppIcon.xcassets` 读取 Xcode App Icon；目录内的 `AppIcon.appiconset` 与发布脚本使用的 `assets/brand/exports/AppIcon.appiconset` 保持同一份已校验资源，避免运行时方形图标覆盖系统图标。`PrivacyInfo.xcprivacy`、`NOTICES.md`、无模型的 `DistributionManifest.json` 和 `SBOM.json` 也作为 Bundle Resources 进入 Store 包；`verify_xcode_store_bundle.py` 会在无签名构建后检查这些资源与能力边界。

正式 Store Target 必须满足：

- 只引用 `WoiceCore` 和已验证的 `WoiceApp` 组合根，不复制领域或录音实现。
- 使用 `Resources/Woice-Store.entitlements`、`Resources/PrivacyInfo.xcprivacy` 和 `Resources/Info.plist`。
- 通过 `WOICE_DISTRIBUTION=app-store` 构建 Store 能力配置；不注册 Process Provider、Unix Socket Agent、自有更新器或自动粘贴。
- Archive/Validate 只能由带有效 Apple Team、Provisioning Profile 和 Store 签名的 Xcode 工程完成。
