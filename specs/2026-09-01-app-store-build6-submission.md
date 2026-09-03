# App Store 0.1.4 Build 6 正式提交规格

> 状态：Build 6 已上传并由 Apple 处理；商店资料与提交审核待完成  
> 日期：2026-09-01  
> 关联计划：[Mac App Store 上架计划](../doc/plan/2026-08-23-mac-app-store-launch.md)

## 目标

- 将当前已验证源码发布为 `Woice 0.1.4 (Build 6)`，生成 `Woice.app` / `com.water.woice` / Store Channel 的无模型 Archive。
- 完成 App Store Connect 上传；Apple 处理完成后，选择 Build 6，补齐商店必填资料并提交 App Review。
- 审核通过前不把状态描述为“已上架”；首次发布保持手动发布，最终公开仍以用户确认和 Apple 状态为准。

## 发布内容

- 包含 Build 5 之后已完成并通过自动门禁的素材命名、异常恢复、详情加载、Qwen 输出清理、重新转写和录音可靠性修复。
- 包含三声道交错麦克风输入统一规范化为最多两声道后再写入 AAC 的修复；用户已在 Dev 安装包完成真实手动录音验收。
- Store 包不携带模型权重；只使用已签名、可验证的线上 Catalog，Catalog 缺少某模型时保持安全回退。

## 边界

- 不上传 Dev App，不读取或修改用户录音、转录、数据库、Keychain 或本机模型。
- 不生成新 Catalog 信任根，不把证书、Team、描述文件、私钥或账号凭据写入仓库和日志。
- Store Edition 继续关闭外部进程 Provider、Unix Socket Agent、自动粘贴和自有更新器。
- 截图必须来自最终功能界面且不包含真实用户隐私；隐私、年龄分级、价格、地区和法律主体字段只使用 App Store Connect 已确认事实。

## 验收标准

- `Resources/Info.plist` 与 `Resources/DistributionManifest.json` 均为 `0.1.4 (Build 6)`。
- `make verify`、`make verify-app-store`、Store 条件构建、资源/隐私/Entitlement 和零模型门禁通过。
- Archive 为双架构、Store Channel、`com.water.woice`，使用有效 Apple 签名，且不存在模型目录。
- 上传日志明确返回成功；随后从 App Store Connect 页面确认 Build 6 的处理状态，而不是仅依赖本机日志。
- 商店版本的截图、描述、关键词、支持 URL、隐私 URL、年龄分级、出口合规、审核联系人和 Review Notes 无缺项后，才点击“提交审核”。
- 提交动作发生前按界面操作安全要求进行最后确认；提交后记录 Apple 返回的准确状态。

## 回滚与停止条件

- 任一自动门禁、签名、Archive、上传处理或 App Store Connect 必填项失败即停止，不回退使用 Build 5。
- 上传成功但处理失败时保留 Build 6 Archive 和原始错误，递增 Build 号后修复；不得覆盖同一 Build。
- 审核拒绝只修复 Apple 指出的范围并新建 Build，不顺手扩大首版能力。

## 当前执行记录

- `make verify` 与 `make verify-app-store` 通过：269 项 Swift Testing、18 项 XCTest、PI/MCP、文档、Harness、资源及零模型 Store Bundle 门禁均成功。
- 已生成并严格验证 `build/Woice-Store-0.1.4-build6.xcarchive`：版本 `0.1.4 (Build 6)`、Bundle ID `com.water.woice`、Store Channel、`x86_64 + arm64`，不含模型权重。
- App Store Connect 上传返回 `Upload succeeded` 与 `Uploaded package is processing`；这只证明上传成功，不等于 Build 已可选、已送审或已上架。
- App Store Connect 当前版本页仍为 `0.1.3`，且缺最终截图、公开隐私政策 URL、审核联系人、版权主体及最终元数据；上述资料确认前不点击“添加以供审核”或“提交以供审核”。
