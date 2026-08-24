# Woice Store 能力裁剪实现规格

> 状态：本机能力裁剪、正式 Store 工程、无签名构建和静态资源门禁已完成；账号、签名、Archive、TestFlight 和审核仍需外部条件
> 日期：2026-08-24
> 计划来源：[Mac App Store 上架计划](../doc/plan/2026-08-23-mac-app-store-launch.md)

## 目标

为 WCL-06/MAS-03 建立单一的 App 组合根能力配置，使 Store Edition 能在编译期关闭外部进程、Unix Socket Agent 和自有更新器，同时保留录音、系统音频、本机转写、HTTP Provider、模型导入和素材导出等核心能力。官网 Core/Offline 默认行为不得改变。

## 范围

- 新增 App 层 `StoreCapabilityProfile`，不让 Domain/Runtime 读取发行宏。
- 通过 SwiftPM 环境 `WOICE_DISTRIBUTION=app-store` 生成 Store 编译配置；未设置时保持官网配置。
- Store 组合根不启动 Pi Unix Socket Connector；设置和工作区不展示 Agent 入口。
- 新增确定性契约测试和静态门禁，验证 Store 能力矩阵与官网能力矩阵。
- 不创建证书、不改变 Bundle ID、不上传 Archive；这些属于 MAS-00/01/02 的外部或正式签名工作包。`project.yml` 已生成正式 `Woice.xcodeproj`，但本机无签名构建不等于 Apple Store 分发完成。

## 不可回归约束

- Woice 仍是录音、转写和素材工具，不变成 Agent 网关。
- Core/Offline 不得因 Store 编译配置而关闭本地录音、转写、模型或导出。
- Store 版不运行任意用户程序、不启动外部 Agent Socket、不读取 CLI 凭据。
- 运行时不以环境变量决定安全能力；环境变量只在 SwiftPM 生成编译设置时使用。

## 验收标准

- `swift build -c release`（未设置 `WOICE_DISTRIBUTION`）通过，官网能力配置为完整能力。
- `WOICE_DISTRIBUTION=app-store swift test --no-parallel` 通过，Store 配置关闭 Process Provider、Unix Socket Agent、自有更新器、自动粘贴和用户可执行文件。
- Store 源码路径只在 App 组合根读取 `StoreCapabilityProfile`；Domain/Runtime 不出现 Store 宏或发行判断。
- Store 配置下 App 启动不会调用 `startPiConnector()`，设置侧栏不包含 Agent 分区。
- `make docs-check harness-check` 与 `git diff --check` 通过；未执行的 Apple 签名、沙盒和审核步骤不得写成通过。
- `make xcode-build-store` 通过 `Woice-Store / Release-AppStore` 无签名编译、链接和 Bundle validation；Bundle 含 `AppIcon.icns`、`Assets.car`、`PrivacyInfo.xcprivacy` 与 `NOTICES.md`。

## 后续未覆盖

MAS-00 的账号/价格/模型许可证决策、MAS-01 正式 Xcode Archive、MAS-02 真正 App Sandbox、MAS-04 Store 模型包体、MAS-05 隐私清单、MAS-06 商店素材、MAS-07 TestFlight 和 MAS-08 提交仍按上架计划逐项推进。
