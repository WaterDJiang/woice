# Woice Mac App Store 提交检查（Build 7）

> 结论：仓库代码、资源和本机 Store 预检可继续；以下“外部”项目必须在 App Store Connect、实体 Mac 或法律/账号侧完成后，才可点击 Submit for Review。

## 已准备

- [x] App Icon 1024×1024 与 macOS 1x/2x 尺寸族。
- [x] SVG 主标、单色主标、文字组合和 Icon Composer 分层源稿。
- [x] Build 7 商店文案、截图顺序和英文 Review Notes（少于 4000 字符）。

## 发布前必须完成

- [x] 已在正式 Xcode Target 接入 `assets/brand/exports/AppIcon.xcassets`，并通过 `make xcode-build-store` 与 AppIcon 资源门禁。
- [x] 已有 1 张真实产品截图：`screenshots/build6/01-material-detail-1280x800.png`，1280×800、不透明 PNG；Build 7 需重新采集或确认画面未受改动。
- [ ] 在 App Store Connect 确认 App Name、Subtitle、描述、关键词、分类、版权信息。
- [x] 隐私政策 URL 与支持 URL 已有公开地址；营销 URL 为可选项，提交前确认可访问性。
- [x] 本机 Bundle 已包含 `PrivacyInfo.xcprivacy`；[Apple 上架资料快照](apple-submission-reference.md)已记录待法律/最终 SDK 审计的项目。
- [x] 完成 Apple Distribution 签名 Archive 和 `destination=export` 的本地 App Store Connect 导出包；深度验签、版本、Bundle ID、双架构和零模型门禁通过。
- [x] 已上传 Build 7；App Store Connect 处理完成，版本页与审核提交均已选择 `0.1.4 (7)`。
- [ ] 完成年龄分级、第三方内容权利、价格/税务和审核联系人；Build 7 出口合规声明已完成。
- [x] 审核测试步骤已写入 `metadata-draft.md`；Build 7 已在实体 Mac 完成“检查更新”、模型清单展示、录音、保存、打开与播放手测。
- [ ] 从干净用户环境复验：无 Agent 时仍可录音、转写、复听、搜索和导出；失败时原始素材仍安全。
- [ ] 录制从启动 App 开始的实体 Mac 审核视频；若展示模型下载，包含 Qwen3-ASR 的实际可用路径。

## 交付证据

- 截图文件名、像素尺寸、色彩空间和 alpha 检查结果。
- 上传 Build 的版本号、Build 号、签名、公证和 App Store Connect 处理状态。
- 隐私政策与商店文案的最终 URL/版本记录。

## 当前停止条件

- `CFBundleVersion` 已递增到 7；Build 6 不得再次提交。
- Catalog v2 已推送并从公开 GitHub Raw 回读验签，包含 Tiny、Qwen3-ASR 和 Large-v3；Review Notes 可以声明 Qwen 已通过签名清单提供。
- Build 7 已完成出口合规、审核回复和重新提交，当前状态为“等待审核”；账号主体、版权人、审核联系人、价格/税务和年龄评级沿用本次已受理提交的 App Store Connect 配置，不在仓库中记录敏感值。
