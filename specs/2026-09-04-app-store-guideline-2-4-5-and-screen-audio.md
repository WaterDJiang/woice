# App Store Guideline 2.4.5 与系统音频说明修复

> 2026-09-05 修订：Build 8 只修复了“导出副本”的保存位置，但原始录音、系统音轨、会议合成和导入素材仍以 App Container 为唯一保存位置，因此再次被 Guideline 2.4.5(i) 拒绝。本修订替代 Build 8 中“App 内素材库工作副本可以长期留在 Container”的判断。

## 目标

- 修复 App Store 审核指出的用户文件写入隐藏 App Container 问题；用户创建或导入的素材文件不再以 Container 内副本作为权威文件。
- 从 Store 版本完全移除非辅助用途的 Accessibility 权限、API 和交互入口。
- 明确说明 ScreenCaptureKit 只采集系统音频，不采集或保存屏幕图像，并补齐隐私政策与审核答复。

## 范围

- Store 版本首次使用素材能力前，通过 macOS 标准保存面板让用户创建一个可直接访问的“Woice 素材”文件夹。
- 使用 security-scoped bookmark 持久化该文件夹权限；权限失效、文件夹被移动或书签失效时必须重新选择，禁止静默回退到 Container 保存新素材。
- 原始麦克风音频、系统音轨、会议合成、导入原件、派生音频、录音块与素材侧车文件统一写入用户选择的素材文件夹。
- SQLite、设置、Keychain 引用、模型、缓存和恢复状态继续留在 App Container；它们不得作为用户素材文件的唯一副本。
- Build 8 及更早版本留在 Container 的素材，在用户选定文件夹后先复制并逐文件校验 SHA-256，再切换权威路径并移除 Container 内旧副本；冲突或校验失败时响亮失败，不覆盖任一副本。
- Store 版本设置页只展示用户选择的素材文件夹，不再展示隐藏 Container 的“原始录音”或“工作区”路径，并提供重新选择入口。
- Store 版本的手动导出继续每次使用标准 `NSSavePanel` 选择用户可访问位置。
- `TextInsertionService`、辅助功能授权入口、模拟 Command-V、手动/自动粘贴在 `WOICE_APP_STORE` 编译中完全排除；复制原文保留。
- ScreenCaptureKit 继续只添加 `.audio` 输出，不添加 `.screen` 输出；隐私政策补齐数据类型、用途、共享、存储、保留和删除说明。
- 版本 Build 递增到 9，并准备新的 Review Notes 与 Resolution Center 回复。

## 不在范围

- 不改变麦克风、本机转写、模型下载和素材数据库的领域语义。
- 不把数据库、设置、模型、缓存或 Keychain 数据迁出 App Container。
- 不新增云端服务、账户、遥测或第三方共享。

## 验收标准

- Store 全新安装首次进入素材流程时显示标准保存面板；取消后不能开始录音或导入，且不能在 Container 创建新的用户素材。
- 用户选择的素材文件夹必须位于 App Container 之外；Store 构建的新录音、双音轨、会议合成和导入文件均实际写入该文件夹。
- Build 8 旧素材迁移前后逐文件 SHA-256 不变；迁移失败时不覆盖目标文件、不丢失源文件，并给出可恢复错误。
- security-scoped bookmark 在重启后可恢复访问；书签失效时阻止新素材写入并要求重新选择。
- Store 构建的每个音频、TXT、JSON、Markdown 手动导出均先显示 `NSSavePanel`，用户取消时不写入用户目录。
- Store 设置页不得显示 App Container 路径，并明确标注素材文件夹“用户可直接访问”。
- Store UI 不出现“粘贴到当前应用”“辅助功能权限”“在 Finder 中显示内部录音”等入口。
- Store 源码/最终二进制门禁不包含 `AXIsProcessTrusted`、`AXIsProcessTrustedWithOptions` 或向全局事件 tap 投递 Command-V 的实现。
- 系统声音采集只向 `SCStream` 注册 `.audio` 输出；没有 `.screen` 输出或屏幕图像文件。
- `PRIVACY.md` 可直接逐项回答 Apple 关于屏幕录制数据的七个问题，并提供可引用的具体原文。
- Build 9 通过迁移/书签/禁止回退测试、单元测试、`make verify`、`make verify-app-store`、签名 Archive 与实体 Mac 手测后才可上传并重新提交。

## 影响面

- `WorkspaceStore`、`AppState`、`WoiceApp`、`RecordingDetailView`、`SettingsView`、Store 验证脚本与相关测试。
- `PRIVACY.md`、App Store 审核资料、发布计划和日志。
