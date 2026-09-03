# App Store 0.1.4 Build 7 商店提交资料与门禁收口规格

> 状态：本机准备完成；Build 7 修复、Catalog v2、Store 门禁、Apple Distribution Archive 和本地导出包已完成，待远端发布、实机材料和 App Store Connect 操作。
> 日期：2026-09-03

## 目标

- 为一次新的 App Store 审核提交准备递增的 `0.1.4 (Build 7)`。
- 修复审核设备点击“检查更新”时因 GitHub Raw 返回 `text/plain` 导致的误报。
- 将仓库中可由产品事实确定的商店资料收口为可粘贴版本：产品描述、审核说明、外部服务、隐私答卷、地区说明和更新说明。
- 建立不伪造外部完成状态的提交门禁：签名、Archive、App Store Connect 处理、截图、实机录屏、账号主体、版权、价格、税务和年龄分级仍以实际外部证据为准。

## 范围

### 代码与发行配置

- `ModelCatalogFetcher` 兼容固定 GitHub Raw 地址返回的 `text/plain; charset=utf-8`，仍执行 JSON、schema、版本、信任根、Ed25519 签名、主机、大小和文件摘要校验。
- `CFBundleVersion` 与 `DistributionManifest.buildVersion` 从 6 递增到 7；不修改历史 Build 6 记录。
- Store Bundle 继续使用 `com.water.woice`、macOS 14.0+、App Sandbox、零随包模型和已验证的 Store capability profile。
- 使用本机已有、不进入 Git 的 Ed25519 发布私钥生成 Catalog v2；保留 Tiny/Large-v3，新增固定 revision 的 Qwen3-ASR 0.6B 4-bit 条目。
- Catalog v2 只发布模型元数据、来源、大小和摘要；Store Bundle 继续不携带任何模型权重。
- 使用登录钥匙串中与 `com.water.woice` 匹配的 Apple Distribution 身份生成 Build 7 Archive 和 App Store Connect 导出包；上传与提交审核状态必须按实际结果记录。

### 商店资料

- `assets/app-store/metadata-draft.md` 收口为 Build 7 候选资料，并提供小于 4000 字符的英文 Review Notes。
- `assets/app-store/app-privacy-draft.md` 与 `PRIVACY.md` 对齐当前实际数据流和第三方服务。
- `assets/app-store/privacy-policy-draft.md`、`submission-checklist.md`、`screenshot-brief.md` 明确已完成项、证据和外部阻塞项。
- 不凭空填写法律主体、版权人、审核联系人、价格/税务、年龄分级、出口合规或实机录屏结果。

## 验收标准

- `make test` 通过；新增的 Catalog `text/plain` 回归测试通过。
- Catalog v2 可由 Store 内置公钥验签，条目精确为 Tiny、Large-v3 和 Qwen3-ASR；三个本机模型包的文件大小与 SHA-256 均与各自 Manifest 一致。
- `make verify-app-store`、`make docs-check`、`make harness-check` 和 `git diff --check` 通过。
- `Resources/Info.plist` 与 `Resources/DistributionManifest.json` 均为 `0.1.4 (Build 7)`。
- Store Bundle 通过 Bundle ID、权限用途、PrivacyInfo、SBOM、NOTICES、能力裁剪、零模型和禁止符号检查。
- Review Notes 不包含凭据、私钥、未验证的“已上传/已批准/已上架”表述，且少于 4000 字符。
- Build 7 Archive 通过深度签名、Bundle ID、版本、架构、Sandbox、资源与零模型门禁；导出包或上传任一失败必须保留原始错误并停止。
- 提交前清单明确要求：最终签名 Build、真实 Mac 截图、实体 Mac 录屏、App Store Connect 隐私答卷、年龄评级、出口合规、价格/税务、版权主体和审核联系人。

## 不在本轮自动完成

- App Store Connect 后台需要账号主体决策的字段，以及 Add for Review、Submit for Review 和最终发布。
- TestFlight/App Review 的 Apple 端处理与审核结果。
- 需要产品/法律主体确认的版权、联系方式、隐私政策法律审定、价格/税务、年龄评级和地区销售范围。
- Catalog v2 的远端发布与 App Store Connect 上传属外部状态变更；只在实际执行并回读成功后才记为完成。

## 回滚与停止条件

- 任一 Store 门禁、实机主流程、签名或 App Store Connect 处理失败即停止提交，不复用被拒 Build 6。
- 不删除用户数据、正式版 App、模型、Keychain 或历史 Archive；只替换同 Channel 的可重建 Dev App。
- 不把本机预检、上传成功或“处理中”写成 Apple 已批准或已上架。
