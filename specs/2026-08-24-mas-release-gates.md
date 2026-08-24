# Woice MAS 本机发行门禁补强规格

> 状态：本机资源与 Archive 前置门禁已完成；正式 Apple 签名、Archive、上传和审核仍需外部凭据
> 日期：2026-08-24
> 计划来源：[当前技术开发收口计划](../doc/plan/2026-08-24-current-technical-development-closure.md) · [Mac App Store 上架计划](../doc/plan/2026-08-23-mac-app-store-launch.md)

## 目标

把 MAS-01、MAS-03、MAS-04 在本机可验证的发行边界继续收紧：

- 正式 `Woice.xcodeproj` 的 Store Bundle 必须带可审计的 `DistributionManifest.json`、`SBOM.json`、`PrivacyInfo.xcprivacy`、`NOTICES.md` 和 AppIcon 资源。
- `make xcode-build-store` 在无签名构建后执行资源、Bundle ID、最低系统版本和 Store 能力清单检查。
- `make archive-app-store` 在调用 Xcode 前要求显式 Store 团队和签名身份，缺少时响亮失败，不把无签名构建当作 Archive 成功。
- 记录当前 Apple 官方上传、截图、隐私清单和审核资料链接，避免商店计划继续依赖过期快照。

## 范围

- 新增静态 Store Xcode 资源模板和资源回归脚本。
- 加强 Store Archive 脚本的签名参数边界；不读取 Keychain 密钥内容，不自动创建证书或配置账号。
- 更新 App Store 资产检查清单和 MAS-00 资料参考。

## 不可回归约束

- `Package.swift` 仍是核心开发/测试真相源，`project.yml` 是 Xcode 工程唯一输入。
- Store Bundle 不得恢复外部 Agent、Unix Socket、Process Provider、自动粘贴或自有更新器。
- 无真实 Apple 凭据时，不创建、上传或伪造签名 Archive、TestFlight 和审核状态。
- 模型权重未完成许可证裁决前，不把模型写入静态 Xcode Store Bundle。

## 验收标准

- `make xcode-build-store` 通过，并检查生成 Bundle 的 `DistributionManifest.json`、`SBOM.json`、`PrivacyInfo.xcprivacy`、`NOTICES.md`、`AppIcon.icns`、`Assets.car`。
- `make archive-app-store` 在未设置 `WOICE_STORE_TEAM_ID` 或 `WOICE_STORE_CODE_SIGN_IDENTITY` 时以可读错误退出；设置后才调用 `xcodebuild archive`。
- `make verify-app-store` 继续覆盖 ad hoc Store 包的能力清单、签名 Entitlements、模型清单和外部 Agent 符号边界。
- Apple 官方参考链接和当前事实写入 `assets/app-store/apple-submission-reference.md`，并在提交清单中标出本机已完成与外部待办。

## 不包含

开发者账号注册、Team/Provisioning Profile 创建、模型权重法律结论、线上隐私政策部署、App Store Connect 上传、TestFlight、人工 TCC/干净用户体验和 App Review。这些继续由 MAS-00～02、MAS-04～08 的外部工作包负责。

## 当前验证结果

- `python3 scripts/test_verify_xcode_store_bundle.py`：2 项通过。
- `make xcode-build-store`：正式 `Woice-Store / Release-AppStore` 无签名编译、链接、Bundle validation 和资源门禁通过。
- `make verify-app-store WOICE_STORE_MODEL_ROOT=...`：Tiny 真实模型包的模型、隐私、SBOM、Entitlements、能力裁剪和外部符号门禁通过。
- `make archive-app-store` 在缺少 `WOICE_STORE_TEAM_ID` 时以“不会伪造 Store 签名 Archive”失败；未调用 Xcode Archive、未上传和未修改安装包。
