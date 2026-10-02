# Woice Mac App Store 提交检查（0.1.6 Build 11）

> 基线：0.1.5 已获 Apple 批准；本表用于 `0.1.6 (Build 11)` 更新，不把本机预检、上传或处理中状态写成审核/发布完成。

## 已准备

- [x] App Icon 1024×1024 与 macOS 1x/2x 尺寸族。
- [x] SVG 主标、单色主标、文字组合和 Icon Composer 分层源稿。
- [x] Build 9 商店文案和英文 Review Notes（少于 4000 字符）。

## 发布前必须完成

- [x] 已在正式 Xcode Target 接入 `assets/brand/exports/AppIcon.xcassets`，并通过 `make xcode-build-store` 与 AppIcon 资源门禁。
- [x] 已有 1 张真实产品截图：`screenshots/build6/01-material-detail-1280x800.png`，1280×800、不透明 PNG；Build 9 需重新采集或确认画面未受改动。
- [ ] 在 App Store Connect 确认 App Name、Subtitle、描述、关键词、分类、版权信息。
- [x] 隐私政策 URL 与支持 URL 已有公开地址；营销 URL 为可选项，提交前确认可访问性。
- [x] 本机 Bundle 已包含 `PrivacyInfo.xcprivacy`；[Apple 上架资料快照](apple-submission-reference.md)已记录待法律/最终 SDK 审计的项目。
- [x] 完成 Apple Distribution 签名 Archive 和 `destination=export` 的本地 App Store Connect 导出包；深度验签、版本、Bundle ID、双架构和零模型门禁通过。
- [x] 已生成并上传 Build 9；App Store Connect 版本页与审核提交均已选择 `0.1.4 (9)`。
- [x] Build 9 出口合规声明已完成；既有年龄分级、价格/销售范围和审核联系人资料随当前提交生效。
- [ ] 在实体 Mac 完成 Build 9 首启选择素材文件夹、录音、导入、Finder 可见、重启持久访问和 Build 8 旧素材迁移手测。
- [ ] 从干净用户环境复验：无 Agent 时仍可录音、转写、复听、搜索和导出；失败时原始素材仍安全。
- [ ] 录制从启动 App 开始的实体 Mac 审核视频；若展示模型下载，包含 Qwen3-ASR 的实际可用路径。

## 交付证据

- 截图文件名、像素尺寸、色彩空间和 alpha 检查结果。
- 上传 Build 的版本号、Build 号、签名、公证和 App Store Connect 处理状态。
- 隐私政策与商店文案的最终 URL/版本记录。

## 当前停止条件

- `CFBundleVersion` 已递增到 9；Build 8 不得再次提交。
- Catalog v2 已推送并从公开 GitHub Raw 回读验签，包含 Tiny、Qwen3-ASR 和 Large-v3；Review Notes 可以声明 Qwen 已通过签名清单提供。
- Build 9 已 Archive、上传、审核批准并手动发布；App Store Connect 当前“可分发”，各地区商店页面可能存在传播延迟。
