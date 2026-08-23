# App Bundle Logo 正式打包规格

状态：本轮实现，待安装后 Finder/LaunchServices 人工验收

## 背景与根因

当前发布脚本只把最新 Logo 的 PNG 复制到 `Contents/Resources`，运行时也会设置 `NSApplication.shared.applicationIconImage`。但 `Resources/Info.plist` 和最终 App Bundle 没有 `CFBundleIconName`/`CFBundleIconFile`，也没有由 Asset Catalog 编译出的 `Assets.car`/`AppIcon.icns`。因此 Finder、Launchpad 和 Dock 无法把最新 Logo 识别为应用图标，只能显示默认图标或旧缓存。

## 目标

- 将已确认的 `assets/brand/exports/AppIcon.appiconset` 通过 Xcode `actool` 编译为 App Bundle 的 `Assets.car` 与 `AppIcon.icns`。
- 把 `CFBundleIconName=AppIcon` 与 `CFBundleIconFile=AppIcon` 写入最终 `Contents/Info.plist`。
- 保留现有 64/1024 PNG，供 Popover 品牌标识和资源审计使用；生产启动不再将原始 PNG 写入 `NSApplication.applicationIconImage`。
- 安装后重新注册 LaunchServices 并刷新 Finder/Dock，使当前用户能看到最新 Logo。

## 不在本轮

- 不重新绘制、改色或替换已确认的品牌母版。
- 不修改菜单栏单色状态图标；菜单栏和 App Bundle 图标是两个不同的展示场景。
- 不引入 XcodeGen 或改变 SwiftPM 构建真相源。

## 实现约束

- 发布脚本在打包时创建临时 `Assets.xcassets/AppIcon.appiconset` 目录，调用 `xcrun --find actool` 定位工具。
- `actool` 输出必须包含 `Assets.car`、`AppIcon.icns` 和 partial Info.plist；缺任一项即失败，不生成带假图标的发布包。
- 生成的 `Contents/Info.plist` 只接受 `actool` 返回的 `CFBundleIconName`/`CFBundleIconFile`，不通过字符串猜测图标资源。
- 打包完成后继续执行 ad hoc 签名和 `codesign --verify --deep --strict`。

## 验收标准

- AC-ICON-001：`make package` 生成的 `Contents/Resources` 同时包含 `Assets.car`、`AppIcon.icns`、`woice-app-icon-64.png` 和 `woice-app-icon-1024.png`。
- AC-ICON-002：最终 `Contents/Info.plist` 的 `CFBundleIconName` 与 `CFBundleIconFile` 均为 `AppIcon`。
- AC-ICON-003：`codesign --verify --deep --strict build/Woice.app` 通过，安装包二进制与构建包一致。
- AC-ICON-004：重新注册 LaunchServices 并刷新 Finder/Dock 后，Finder/Launchpad 显示最新 W Logo；菜单栏仍显示单色状态图标。
- AC-ICON-005：`make docs-check`、`make harness-check`、`make verify` 和 `make install` 通过。

## 替代、保留、迁移、停止、顺序

- 替代：替代“只复制 PNG、依赖运行时设置图标”的发布方式。
- 保留：PNG 资源、AppIcon Asset Catalog 和菜单栏单色图标；Bundle AppIcon 是 Dock/Finder/Launchpad 唯一系统图标来源。
- 迁移：新包从 Asset Catalog 生成系统识别的 App Bundle 图标；旧安装包不做文件内修改，重新安装覆盖。
- 停止：停止生成缺少 Bundle 图标元数据的可安装包；停止运行时原始 PNG 覆盖 Bundle AppIcon。
- 顺序：更新规格 -> 编译 Asset Catalog -> 合并 Info.plist -> 签名/校验 -> 安装 -> 刷新 LaunchServices。
