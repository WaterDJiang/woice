# Dev / Store App 命名、隔离与旧包清理

> 状态：命名、运行时隔离、安装后残留清理与自动门禁完成

## 目标

- 本地开发 App 在 Finder、Dock 和 Launchpad 中统一显示为 `Woice (Dev)`。
- App Store / TestFlight App 继续显示为 `Woice`。
- 每次生成或安装新的本地开发 App 前，清理可重建的旧 App Bundle，不再向 Launchpad 留下多个顶层副本。
- Dev 与正式版使用独立数据、Keychain、单实例锁和本地 RPC 路径，可以同时安装和运行。

## 范围

- `Release-Direct` 和 `make package/install` 的本地开发产物。
- `package_distribution.py` 的 Dev / Core / Offline / Store 显示名契约。
- `make install` 对历史本地 App 和新 Dev App 的安全替换。
- App Channel 对 Application Support、Keychain service、实例锁和 Socket 的单一投影。
- `AGENTS.md` 的持久项目规则。

## 不在范围

- 不删除 `~/Library/Application Support/Woice`、Keychain、录音、模型、数据库或设置。
- Store Archive 只保留当前待上传的最新一份；旧 Archive 可恢复移入废纸篓。DMG、Release 资产和 Store 上传证据不自动删除。
- 不改变 Bundle ID：Dev/Direct 保持 `com.woice.app`，Store 保持 `com.water.woice`。
- 不将 Core / Offline 公开分发包改名为 Dev。
- 不自动把正式录音、模型、设置或密钥复制到 Dev。

## 行为契约

- Dev：Bundle 文件名、`CFBundleDisplayName` 和 `CFBundleName` 为 `Woice (Dev)`；安装路径为 `/Applications/Woice (Dev).app`。
- Store：Bundle 文件名、`CFBundleDisplayName` 和 `CFBundleName` 为 `Woice`；归档与上传路径保持现状。
- Bundle 必须包含 `WOICEAppChannel=dev|release|store`；未知值不得投影到 Dev 数据。
- Dev 使用 `~/Library/Application Support/Woice Dev`、Keychain service `com.woice.app.dev`、该目录下的 `instance.lock` 和 `woice.sock`。
- Direct 正式版继续使用 `~/Library/Application Support/Woice`、Keychain service `com.woice.app`，不迁移或改名现有数据。
- Store 使用 App Sandbox 的正式 Application Support 容器和 Keychain service `com.water.woice`；不启动外部 Connector。
- 新建 Dev Bundle 前清理项目 `build/` 顶层的已知 Woice App Bundle；安装完成后再次清理该副本，并清理 `.build/xcode-*-derived/Build/Products` 中可重建的 Woice App，避免 Spotlight 重复展示。
- 安装 Dev Bundle 前，先退出同 Bundle ID 的旧 Dev 进程，再删除精确目标 `/Applications/Woice (Dev).app`后复制。
- 新 App 复制并验明存在后，旧安装目标和项目构建副本不得继续保留；系统应用目录中同一 Channel 只保留最新一份。
- 若 `/Applications/Woice.app` 的 Bundle ID 是历史 Dev ID `com.woice.app`，将它移入废纸篓；若是 Store ID `com.water.woice`，必须保留。
- 新 Store Archive/导出包生成后，旧 Woice `.xcarchive` 移入废纸篓，只保留当前待上传 Archive；不得删除其中仍需上传或审计的最新一份。
- 清理脚本对未知路径、非 `.app` 目标、非预期 Bundle ID 一律 fail-closed。

## 验收标准

- AC-01：Dev 包显示名与安装文件名均为 `Woice (Dev)`，Bundle ID 为 `com.woice.app`。
- AC-02：Store 包显示名与归档产品名均为 `Woice`，Bundle ID 为 `com.water.woice`。
- AC-03：连续两次生成 Dev 包后，`build/` 顶层只留一个 `Woice (Dev).app`。
- AC-04：安装 Dev 包时可清理历史 `com.woice.app` 的 `/Applications/Woice.app`，但不会删除 `com.water.woice` 的 Store App。
- AC-05：自动测试覆盖命名投影、顶层构建副本清理、Store 保护、用户数据与 Archive 不受影响。
- AC-06：Dev/Direct/Store 的 App Channel 从 Bundle 元数据确定性解析，三者 Keychain service 不重合。
- AC-07：Dev 与 Direct 的 Workspace root、`instance.lock` 和 `woice.sock` 路径不重合；单实例锁不阻止另一 Channel 启动。
- AC-08：既有 `Application Support/Woice` 和 `com.woice.app` Keychain 不会在 Dev 首启时被复制、修改或删除。
- AC-09：`make install` 完成后只保留 `/Applications/Woice (Dev).app`，项目顶层和 Xcode Derived Products 不残留可重建 Woice App。
- AC-10：旧 Store Archive 可恢复清理，当前待上传 Archive、导出 PKG 和用户数据保持不变。

## 影响面

- `project.yml`、`Resources/Info.plist`、`Makefile`、`Woice.xcodeproj`。
- `scripts/package_distribution.py` 及本地 App 清理脚本/测试。
- App Channel、Storage、Keychain、SingleInstanceGuard、Connector 默认 Socket 路径。
- 本机安装路径、启动/无障碍验收脚本默认路径。
- `AGENTS.md`、spec/log 索引。

## 验证结果

- `make verify` 通过：232 项 Swift、PI 7 项、MCP 2 项，以及文档、Harness、格式、发行清单、Channel、命名与清理脚本门禁。
- `make xcode-build-store` 通过；正式无签名 Store 产物为 `Woice.app` / `com.water.woice` / `Woice` / `WOICEAppChannel=store`。
- Dev 打包产物为 `build/Woice (Dev).app` / `com.woice.app` / `Woice (Dev)` / `WOICEAppChannel=dev`，`build/` 顶层只保留该 App。
- Channel 单测确认 Dev / Direct / Store 的 Keychain service 不重合，Dev 与 Direct 的 Workspace root 不重合；PI 测试确认 Dev / release Socket 不重合且 Store 不提供外部 Socket。
- 本机已安装 `0.1.4 (Build 4)` 的 `/Applications/Woice (Dev).app`，严格验签、启动和独立 Dev 数据目录通过。
- 2026-08-31 残留清理后，`build/` 顶层与 `.build/xcode-*-derived/Build/Products` 不再保留 Woice App；Build 1–3 Store Archive 已可恢复移入废纸篓，只保留 Build 4 当前待上传 Archive 和导出 PKG。
- 清理脚本 6 项测试通过，覆盖顶层 App、Derived Products、旧 Archive、Store App 保护、未知身份拒绝与可恢复移动。
