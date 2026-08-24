# Woice Mac App Store 提交检查

## 已准备

- [x] App Icon 1024×1024 与 macOS 1x/2x 尺寸族。
- [x] SVG 主标、单色主标、文字组合和 Icon Composer 分层源稿。
- [x] 商店文案草案、截图顺序和审核说明骨架。

## 发布前必须完成

- [x] 已在正式 Xcode Target 接入 `assets/brand/exports/AppIcon.xcassets`，并通过 `make xcode-build-store` 与 AppIcon 资源门禁。
- [ ] 使用最终签名 Build 采集 1–10 张 Mac 16:10 截图，导出为不透明 PNG/JPEG；当前推荐 `2560×1600`。
- [ ] 确认 App Name、Subtitle、描述、关键词、分类、版权信息。
- [ ] 补齐隐私政策 URL、支持 URL、营销 URL（如使用）。
- [x] 本机 Bundle 已包含 `PrivacyInfo.xcprivacy`；[Apple 上架资料快照](apple-submission-reference.md)已记录待法律/最终 SDK 审计的项目。
- [ ] 完成 Developer ID / App Store 签名、公证和上传 Build；确认版本号、Build 号与 Bundle ID 关联正确。
- [ ] 完成年龄分级、出口合规、内容权利和审核测试步骤。
- [ ] 从干净用户环境复验：无 Agent 时仍可录音、转写、复听、搜索和导出；失败时原始素材仍安全。

## 交付证据

- 截图文件名、像素尺寸、色彩空间和 alpha 检查结果。
- 上传 Build 的版本号、Build 号、签名、公证和 App Store Connect 处理状态。
- 隐私政策与商店文案的最终 URL/版本记录。
