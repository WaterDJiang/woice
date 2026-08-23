# 模型下载状态显示修正

> 状态：实现规格
> 日期：2026-08-22
> 关联：[模型接入计划](../plan/2026-08-22-model-integration.md) · [设置页体验](2026-08-22-settings-menu-experience.md)

## 问题

Tiny 与 Large-v3 下载按钮共用 `AppState.isDownloadingModel`。实际只允许一个下载任务运行，但任意任务运行时两个按钮都会显示“下载中…”，进度条也可能固定显示在 Tiny 区块下。

## 目标

- 活动下载必须按 `packID + revision` 绑定到对应模型卡片。
- 非活动模型显示“等待当前下载”，不能伪装成正在下载。
- 进度文件名和百分比只显示在实际活动模型下。
- 保留单任务互斥，避免同时下载两个模型造成磁盘和网络竞争。

## 验收标准

- AC-MDL-001：点击 Tiny 后，只有 Tiny 显示“下载中…”和进度；Large 显示“等待当前下载”。
- AC-MDL-002：点击 Large-v3 后，只有 Large-v3 显示“下载中…”和进度；Tiny 显示“等待当前下载”。
- AC-MDL-003：下载任务的持久化 `packID`、`version` 与 UI 活动卡片一致。
- AC-MDL-004：下载互斥仍然有效，第二个按钮不可启动并发下载。
- AC-MDL-005：下载完成、失败、暂停后，两个卡片都恢复准确状态，不残留“下载中…”。

## 影响面

- `Sources/WoiceApp/AppState.swift`：提供按模型清单判断活动下载的方法。
- `Sources/WoiceApp/SettingsView.swift`：按活动模型渲染按钮和进度。
