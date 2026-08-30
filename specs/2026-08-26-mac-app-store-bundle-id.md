# Woice Mac App Store Bundle ID 迁移

## 目标

为 Woice 的 Mac App Store 发行使用已确认的新 Explicit Bundle ID `com.water.woice`，解决原 `com.woice.app` 在当前 Apple Developer 团队不可用的问题。

## 范围

- 在 Apple Developer 账户注册 `com.water.woice` App ID。
- 在项目组合根、Info.plist、Store 资源和相关验证契约中同步 Bundle ID。
- 在 App Store Connect 创建一个 macOS App 记录：名称 `Woice`，SKU `woice-macos-001`。
- 为 Store Archive 只在 Woice App Target 配置 App Store 描述文件；Swift Package 依赖保持 Automatic，避免把产品描述文件错误传给库 Target。
- 保持 GitHub Core/Offline 安装包、模型策略和现有未相关工作树改动不变。

## 不在范围

- 不创建第二个商店 App。
- 不改变版本号、模型内容、价格、隐私政策文案或公开发布渠道。
- 不提交 Apple 密码、验证码、证书私钥、Provisioning Profile 或本机签名身份。

## 验收标准

- Apple Developer 标识符中存在 Explicit App ID `com.water.woice`，且未额外启用不需要的能力。
- `project.yml`、`Resources/Info.plist` 及相关 Store 构建配置使用 `com.water.woice`。
- `make xcode-project` 成功生成工程。
- `make xcode-build-store` 成功完成 Store Target 无签名编译与资源门禁。
- Store Archive 的签名证书与描述文件包含的证书一致，且依赖 Target 不因手动描述文件设置而失败。
- App Store Connect 中存在 macOS App `Woice`，Bundle ID 为 `com.water.woice`，SKU 为 `woice-macos-001`。
- 记录 Apple ID 注册、项目验证和 App Store Connect 建记录结果；不宣称已上传构建包或已通过审核。

## 影响面

- App 身份从 `com.woice.app` 变更为 `com.water.woice`；这会影响签名、Provisioning Profile、App Store Connect 记录以及已有安装包的更新链路。
- GitHub 既有 Release 资产不回写、不删除；后续新包必须使用新 Bundle ID 重新签名。
