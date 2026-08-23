# Woice Mac App Store 上架计划

> 状态：待实施（仅记录，不自动启动）  
> 日期：2026-08-23  
> 启动条件：用户明确要求“启动上架计划”后，才进入 MAS-00；未启动前不创建证书、不改 Bundle ID、不启用沙盒、不上传 Build、不提交审核  
> 当前路线图：[当前路线图与计划迁移表](2026-08-22-current-roadmap-and-plan-transition.md)  
> 相关计划：[M2-08 模型接入与双版本发布](2026-08-22-model-integration.md) · [旧总计划 M1-07 发布门禁](2026-08-22-m0-mvp.md)

## 1. 计划关系与冲突裁决

- 替代：不替代 M1-07 的官网发行签名、公证、Staple 和隐私门禁；不替代 M2-08i 的 Core/Offline 双发行、模型缓存和真实会议验收。
- 保留：官网继续提供 Core/Offline 两种 DMG；现有录音、双轨、meetingMix 单次 ASR、模型版本、素材不可变、Keychain 和外发确认规则全部保留。
- 迁移：Mac App Store 专属的 Xcode Archive、App Sandbox、Store 能力裁剪、App Store Connect 元数据、TestFlight 和 App Review 全部进入本计划，不再混入 M1-07/M2-08i。
- 停止：未停止现有开发计划；Store Edition 首版停止暴露任意外部进程 Provider、现有外部 Unix Socket Agent Connector 和自有更新器。
- 顺序：本计划保持“待实施”；用户启动后可先做账号/资料准备，但工程改造排在 R0/R1/R2 核心发布门禁之后或与其不冲突地独立进行。M2-09 Agent 协作不是上架前置。

## 2. 首版发行裁决

### 2.1 推荐形态

- Mac App Store 只建立一个 Woice App 记录，不把 Core/Offline 做成两个近似商店 App。
- 商店首版默认开箱可用，候选方案为内置已验证的 WhisperKit Large-v3，并保留 macOS on-device Speech 作为安全回退。
- 官网继续保留：
  - Core：小体积、不内置 WhisperKit 权重，允许用户配置本机/局域网/云端模型。
  - Offline：内置默认模型，开箱即用。
- 商店版允许用户导入模型文件夹、连接本机 HTTP ASR、配置 OpenAI-compatible ASR；不执行用户指定的任意程序。

### 2.2 启动时必须确认的产品决策

- [ ] 开发者主体：个人或公司。
- [ ] 最终开发者显示名称。
- [ ] 最终 Bundle ID；首次上传后不再更换。
- [ ] 商店首版是否内置 Large-v3；若许可证或包体门禁不通过，改为 Tiny + Speech。
- [ ] 免费、一次性付费或 StoreKit 内购模式。
- [ ] 首发国家/地区和中文、英文商店页范围。
- [ ] 是否在首版保留自动粘贴；默认方案为关闭自动粘贴，只保留复制。

## 3. 当前基础与缺口

| 项目 | 当前事实 | 上架缺口 |
|---|---|---|
| 构建 | SwiftPM 可执行目标，手工组装 `.app`/DMG | 缺正式 Xcode macOS App Target、Archive 和 App Store Connect 上传链 |
| 签名 | Core/Offline 为 ad hoc，`TeamIdentifier=not set` | 缺开发团队、App Store 分发签名和 Provisioning Profile |
| 沙盒 | 当前包没有 App Sandbox Entitlement | 必须启用沙盒并逐项收敛文件、网络、麦克风和进程权限 |
| 体积 | Core 约 9.4 MB，Offline 约 610 MB | 体积本身可控；仍需模型许可证、包清单和下载体验裁决 |
| 隐私 | Info.plist 已有麦克风、系统声音和语音识别用途说明 | 缺 `PrivacyInfo.xcprivacy`、线上隐私政策和 App Privacy 答卷 |
| 模型 | Large-v3 已完成严格基准，默认路由已冻结 | 需确认权重再分发许可证、Store Bundle 清单及审核可测试性 |
| 外部能力 | HTTP Provider、Process Provider、Unix Socket RPC/Agent 均有基础 | Process 与外部 Socket 不适合作为 Store 首版能力，需编译期能力裁剪 |
| 系统音频 | ScreenCaptureKit 双轨和 meetingMix 已有真实样本验收 | 需在 Store 签名和沙盒下重新完成 TCC/真实会议矩阵 |
| 商店资产 | 已有 App Icon 和部分商店素材草案 | 缺最终截图、描述、关键词、支持 URL、隐私 URL、审核备注 |

## 4. 必须准备清单

### 4.1 账号与法律主体

- [ ] 加入 Apple Developer Program，并保持会员有效。
- [ ] 公司主体准备合法实体名称、D-U-N-S 编码、企业域名邮箱和可访问官网；个人主体确认商店将显示个人姓名。
- [ ] Account Holder 接受最新协议。
- [ ] 若采用付费或内购，完成税务、银行与付费应用协议。
- [ ] 确认商标、产品名称和域名可长期使用。

### 4.2 App Store Connect 资料

- [ ] 创建 macOS App 记录：名称、主语言、Bundle ID、SKU、访问范围。
- [ ] 确定分类、年龄评级、价格、税务类别和销售区域。
- [ ] 准备 30 字以内副标题、完整描述、关键词、版本更新说明。
- [ ] 准备隐私政策 URL、支持 URL、市场官网 URL 和联系邮箱。
- [ ] 准备至少 1 张、最多 10 张真实 macOS 截图；首版目标 6 张。
- [ ] 准备审核联系人、联系电话和 Review Notes。
- [ ] 完成出口合规/加密问卷；如只使用系统标准 TLS，仍按实际实现准确回答，不预填结论。

### 4.3 许可证与第三方材料

- [ ] 核对 WhisperKit 精确版本、许可证和 Notices。
- [ ] 核对默认 Tiny/Large-v3 权重的精确 revision、来源、再分发权和使用限制。
- [ ] 为每个 bundled model 记录文件清单、SHA-256、体积和 SBOM/Notices 指针。
- [ ] 核对所有 Swift Package、资源、字体、图标和截图素材的商用/再分发权限。
- [ ] 未通过许可证门禁的模型不得进入 Store Bundle。

## 5. Store Edition 能力矩阵

| 能力 | Store 首版 | 官网版 | 裁决 |
|---|---:|---:|---|
| 麦克风录音 | 保留 | 保留 | 用户主动开始，持续显示录音状态 |
| ScreenCaptureKit 系统声音 | 保留 | 保留 | 会议模式默认关闭，不保存屏幕图像 |
| 双原轨与 meetingMix | 保留 | 保留 | 原轨不可变，默认 meetingMix 单次 ASR |
| WhisperKit 内置模型 | 保留 | Offline 保留 | Store 首版优先开箱可用 |
| 用户导入模型 | 保留 | 保留 | 通过系统文件选择器导入并复制到容器，先校验后注册 |
| localhost/局域网 HTTP ASR | 保留 | 保留 | 仅出站网络；公网发现继续 fail-closed |
| 云端 ASR | 保留 | 保留 | 首次和实际外发前显示目标、文件与请求数 |
| 用户指定可执行文件 | 关闭 | 保留 | Store 不执行容器外任意程序 |
| Process Provider | 关闭 | 保留 | Store 首版不启动外部进程 |
| 外部 Unix Socket Agent | 关闭 | 保留 | 外部 Agent 无法自然访问 Store App Container |
| 自动粘贴 | 默认关闭待审核 | 可保留 | 首版优先复制；若保留则必须显式授权和真实审核说明 |
| 自有更新器 | 禁止 | 可选 | Store 更新只通过 Mac App Store |

## 6. 工作包

### MAS-00：启动审计与决策冻结

状态：待实施。

- 重新检查 Apple 当前上传工具链、审核指南、隐私清单和截图规格。
- 重新检查当前 Bundle、Entitlement、签名、模型体积和许可证，不复用过期快照。
- 完成第 2.2 节产品决策并冻结 Store 首版能力矩阵。
- 输出 Store 上架风险清单；P0 未关闭不得进入工程改造。

退出条件：账号主体、Bundle ID、价格、默认模型、首发地区和首版能力均有书面结论。

### MAS-01：正式 Xcode Store Target

状态：待实施。

- 在计划结构 `App/WoiceApp/` 建立正式 macOS App Target，引用现有 SwiftPM 模块，不复制业务实现。
- 建立 `Debug`、`Release-Direct`、`Release-AppStore` 配置，避免条件判断散落在 View/Runtime。
- 配置 App Icon、Info.plist、版本号、Build Number、签名团队和 Archive Scheme。
- 使用当前 App Store 接受的 Xcode/SDK；实施启动时重新确认，不把 Xcode 16.4 直接当作提交基线。
- 保留当前 SwiftPM 为核心开发真相源；Xcode Target 只承担 App 组合根、Entitlement、资源和发行。

退出条件：`Product > Archive` 成功，Organizer Validate 不存在签名、Bundle、图标和结构错误。

### MAS-02：App Sandbox 与数据容器

状态：待实施。

- 启用 App Sandbox。
- 只申请经过用例证明的麦克风、出站网络、用户选择文件读写等权限。
- 录音、数据库、转写、任务和模型默认写入 App Container。
- 导入/导出统一走 `NSOpenPanel`/`NSSavePanel`；导入模型默认复制进容器。
- 如确需持续访问外部目录，使用 security-scoped bookmark，并覆盖吊销、移动和失效恢复。
- Keychain 只保存密钥；重新验证 Store Team/Access Group 下的读写和升级兼容。

退出条件：沙盒开启后录音、转写、复听、搜索、导出、Keychain 和模型导入主链路通过；应用不依赖容器外隐式路径。

### MAS-03：Store 能力裁剪与组件边界

状态：待实施。

- 在 App 组合根注册 `StoreCapabilityProfile`，Domain/Runtime 不读取编译宏。
- Store 组合根不注册 Process Provider、外部 Unix Socket Connector、自有更新器和任意 Shell/CLI 能力。
- HTTP Provider 只保留客户端连接能力，不启动、安装或管理外部模型服务。
- UI 根据能力配置隐藏不可用入口，不显示点击后必然失败的控件。
- 官网配置保持现有能力，不因 Store 裁剪发生功能回退。

退出条件：Store Bundle 静态检查不包含外部进程启动入口；Core/Offline 官网回归保持通过。

### MAS-04：Store 模型交付

状态：待实施。

- 对默认模型执行许可证、revision、SHA-256、SBOM、Notices 和包体门禁。
- 商店首版候选内置 Large-v3；如许可证或性能门禁失败，显式改为 Tiny + Speech，不自动切云端。
- 用户模型采用“选择文件夹 -> 校验 -> 复制到容器 -> 原子注册 -> 显式切换”流程。
- 下载模型仍视为附加数据，不允许下载可执行代码、dylib、Swift bundle 或运行时安装器。
- Apple-hosted Background Assets 仅作为 macOS 26+ 后续评估，不阻塞当前 macOS 14 最低版本。

退出条件：全新安装无需 API Key 即可完成录音到本机转写；模型缺失/损坏保持原音频安全且不隐式外发。

### MAS-05：权限、隐私与审核可解释性

状态：待实施。

- 新增有效的 `PrivacyInfo.xcprivacy` 并进入 `Contents/Resources`。
- 逐项核对麦克风、系统音频、语音识别和辅助功能用途文案。
- 发布线上隐私政策，覆盖本地存储、云端外发、API Key、删除、系统声音和第三方服务。
- 完成 App Privacy 数据类型问卷，并包含第三方 SDK 实际行为。
- Review Notes 明确：ScreenCaptureKit 只取用户主动开启的系统声音，Woice 不保存屏幕画面。
- 审核账号原则为无需登录；如后续增加账户，提供可用审核账号和完整操作路径。

退出条件：Privacy Report、隐私政策、App Privacy 答卷和实际网络/存储行为一致。

### MAS-06：商店页面与素材

状态：待实施。

- 复用已定稿 Woice W 波形 App Icon，验证 Finder、Dock、Launchpad 和 Store 展示。
- 产出 6 张真实产品截图：快速录音、会议双轨、本机转写、录音详情、模型设置、素材搜索/导出。
- 截图不伪造系统权限、模型状态、连接状态或识别结果。
- 完成简体中文和英文名称、副标题、描述、关键词和版本说明。
- 商店描述明确兼容 Apple Silicon 与最低 macOS 版本。

退出条件：App Store Connect 元数据无缺项，截图来自待提交 Build 的真实界面。

### MAS-07：TestFlight 与真实 Mac 验收

状态：待实施。

- 内部 TestFlight 覆盖干净账号、覆盖安装、升级、离线、网络异常和模型损坏。
- 外部 TestFlight 覆盖目标用户的首次启动理解、权限拒绝恢复和模型/录音体验。
- 权限矩阵：麦克风拒绝/允许，系统声音拒绝/允许，辅助功能拒绝/允许。
- 音频矩阵：麦克风、全桌面系统声音、窗口级声音、真实会议、长录音、睡眠、设备变化、崩溃和磁盘不足。
- 模型矩阵：内置模型、Speech 回退、导入模型、localhost 服务、云端外发取消/确认。
- 无障碍矩阵：浅色、深色、高对比、键盘、VoiceOver、Reduce Motion。

退出条件：P0/P1 问题为 0；至少一个非开发账号完成“安装 -> 录音 -> 转写 -> 复听 -> 导出”。

### MAS-08：提交与审核处理

状态：待实施。

- 选择经 TestFlight 验收的唯一 Build。
- 完成价格、地区、年龄评级、出口合规、隐私和审核联系信息。
- 提供无需外部服务的最短审核路径：授权麦克风 -> 录音 -> 停止 -> 本机转写 -> 历史复听。
- 在 Review Notes 提供会议模式、系统音频、模型来源、云端外发和辅助功能的解释。
- 首次发布选择手动发布；审核通过后由用户确认实际上架时间。
- 审核问题只按原问题修正并重提，不顺手扩大首版范围。

退出条件：状态为 Approved/Ready for Distribution；用户明确确认后才发布，不把“已上传”记录为“已上架”。

## 7. 计划新增门禁

实施时新增以下命令；当前尚不存在，不得提前写成已通过：

```bash
make verify-app-store
make archive-app-store
make acceptance-app-store-sandbox
make acceptance-app-store-clean-user
```

`make verify-app-store` 至少检查：

- App Sandbox 已启用。
- 非 ad hoc、Team Identifier 存在。
- Bundle ID、版本、Build、图标和隐私清单完整。
- Store Bundle 不包含 Process Provider/Unix Socket Server/自有更新器入口。
- bundled model Manifest、SHA-256、Notices 和许可证齐全。
- `codesign --verify --deep --strict` 与 Xcode Validate 通过。

## 8. 审核说明模板要点

- Woice 是用户主动控制的本地优先录音和转写工具，不在后台隐蔽录音。
- 默认转写在本机完成，不需要登录或 API Key。
- 会议模式默认关闭；开启后 ScreenCaptureKit 只捕获系统音频，不保存屏幕图像。
- 麦克风和系统声音作为不可变原轨保存；统一回放和默认转写使用可重建 meetingMix。
- 只有用户选择外部 Provider 并确认后，音频才会发送到指定服务。
- API Key 只保存到 macOS Keychain。
- 首版 Store Edition 不执行用户指定程序，不安装外部组件，不包含自有更新器。

## 9. 风险与处理顺序

| 风险 | 等级 | 处理 |
|---|---:|---|
| 沙盒导致现有路径、Unix Socket、Process Provider 失效 | P0 | Store 组合根裁剪；先完成沙盒主链路再做商店素材 |
| 系统音频在 Store 签名下 TCC 行为变化 | P0 | TestFlight/Store 签名真实会议验收，不复用 ad hoc 授权结论 |
| 模型权重再分发许可证不完整 | P0 | 未通过则不打包 Large，启用 Tiny/Speech 明确替代方案 |
| 审核员无法开箱完成转写 | P0 | Store 首版内置可用模型并提供最短审核步骤 |
| 自动粘贴触发辅助功能审核疑问 | P1 | 首版默认关闭；复制主路径保持完整 |
| 两个近似 App 记录造成重复审核风险 | P1 | Store 只保留一个 Woice，双版本留在官网 |
| Store 与官网能力条件分散 | P1 | 单一 `StoreCapabilityProfile`，只在 App 组合根切换 |

## 10. 官方规则入口

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [Create an App Store Connect app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)
- [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)

## 11. 启动口令与暂停边界

- 用户说“启动上架计划”：从 MAS-00 开始，只做当前工作包，不自动提交审核。
- 用户说“准备 TestFlight”：必须先满足 MAS-00 至 MAS-06 的退出条件。
- 用户说“提交审核”：必须先满足 MAS-07，并再次确认价格、地区、隐私答卷和 Review Notes。
- 用户说“正式发布”：只在审核通过后选择上架时间；此前任何状态都不得描述为已发布。
