# App Store Guideline 2.4.5 与系统音频说明修复

## 目标

- 修复 App Store 审核指出的用户文件写入隐藏 App Container 问题。
- 从 Store 版本完全移除非辅助用途的 Accessibility 权限、API 和交互入口。
- 明确说明 ScreenCaptureKit 只采集系统音频，不采集或保存屏幕图像，并补齐隐私政策与审核答复。

## 范围

- Store 版本的素材导出改为每次使用标准 `NSSavePanel` 选择用户可访问位置。
- Store 版本不再提供打开或在 Finder 中显示 App Container 内部文件的入口；容器只保存数据库、恢复状态、缓存和 App 内素材库工作副本。
- `TextInsertionService`、辅助功能授权入口、模拟 Command-V、手动/自动粘贴在 `WOICE_APP_STORE` 编译中完全排除；复制原文保留。
- ScreenCaptureKit 继续只添加 `.audio` 输出，不添加 `.screen` 输出；隐私政策补齐数据类型、用途、共享、存储、保留和删除说明。
- 版本 Build 递增到 8，并准备新的 Review Notes 与 Resolution Center 回复。

## 不在范围

- 不改变麦克风、本机转写、模型下载、素材数据库和录音恢复机制。
- 不删除用户已有录音或迁移现有 App Container。
- 不新增云端服务、账户、遥测或第三方共享。

## 验收标准

- Store 构建的每个音频、TXT、JSON、Markdown 导出均先显示 `NSSavePanel`，用户取消时不写入用户目录。
- Store UI 不出现“粘贴到当前应用”“辅助功能权限”“在 Finder 中显示内部录音”等入口。
- Store 源码/最终二进制门禁不包含 `AXIsProcessTrusted`、`AXIsProcessTrustedWithOptions` 或向全局事件 tap 投递 Command-V 的实现。
- 系统声音采集只向 `SCStream` 注册 `.audio` 输出；没有 `.screen` 输出或屏幕图像文件。
- `PRIVACY.md` 可直接逐项回答 Apple 关于屏幕录制数据的七个问题，并提供可引用的具体原文。
- Build 8 通过单元测试、`make verify`、`make verify-app-store`、签名 Archive 与实体 Mac 手测后才可上传并重新提交。

## 影响面

- `RecordingDetailView`、`AppState`、`TextInsertionService`、`SettingsView`、Store 验证脚本与相关测试。
- `PRIVACY.md`、App Store 审核资料、发布计划和日志。
