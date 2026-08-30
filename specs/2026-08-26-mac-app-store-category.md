# Woice Mac App Store 类别元数据

## 目标

为正式 Mac App Store Archive 增加 Apple 要求的 `LSApplicationCategoryType`，使 Organizer Validate 能识别 Woice 的商店类别。

## 范围

- 在共享 App `Info.plist` 根字典中声明 Productivity 类别：`public.app-category.productivity`。
- 在 Store Bundle 静态验证和回归 Fixture 中锁定该元数据，避免后续 Archive 再次缺失。
- 重新生成 Xcode 工程、构建并生成版本 `0.1.3` 的 Store Distribution Archive。

## 不在范围

- 不修改 Bundle ID、签名、Provisioning Profile、版本号或 Build 号。
- 不代替 Organizer Validate、App Store Connect 上传或审核。

## 验收标准

- `Resources/Info.plist` 包含合法的 `LSApplicationCategoryType` 值 `public.app-category.productivity`。
- `make xcode-build-store` 与 Store Bundle 验证通过。
- 新 Archive 的 `Contents/Info.plist` 包含同一类别值，且签名验证通过。
- 文档记录原始 Apple 错误、修复和本机验证结果。
