# Woice 技术开发收口实现规格

> 状态：WCL-00～03、WCL-05 已完成源码与自动门禁；WCL-04 发行验证阻塞  
> 日期：2026-08-24  
> 计划来源：[当前技术开发收口计划](../doc/plan/2026-08-24-current-technical-development-closure.md)

## 目标

把 WCL-01～05 中可由源码和自动化门禁证明的部分收口：

- 侧栏顶/中/底布局具有确定性几何规则，最小宽度下文案和路由不回归。
- 长文件分段、失败/超时/拒绝外发和重启恢复保持本地优先、幂等和原始 Artifact 不覆盖。
- 麦克风、系统声音、Speech、辅助功能的状态映射和关键控件可访问语义有纯代码回归。
- Agent 入站具备独立的只读/创建任务/录音控制权限策略；录音控制默认拒绝，外部请求不能绕过用户确认。
- 发行脚本提供 Developer ID、Hardened Runtime、Notarization、Staple、本地 `ReleaseManifest.json` 和远程产物读回门禁；缺少凭据或远程状态/大小/摘要不一致时显式失败。

## 范围

包含：`Sources/WoiceCore` 的可测试策略、`Sources/WoiceApp` 的组合和 UI 接线、Swift 测试、Make 目标、发行脚本与计划/日志更新。

不包含：Mac App Store MAS-00～08、真实用户会议准确率、手动 TCC 撤销/授权、第三方生产 Catalog 凭据、公证服务凭据和真实 Agent 账户登录；这些必须保留为明确的外部验收或阻塞。

## 不可回归约束

- 原始音频、原始视频和既有 Transcript Artifact 不原位覆盖。
- 本地 Provider 失败不自动把音频或文字切换到云端。
- 普通复制不申请辅助功能；自动粘贴、外发和录音控制必须有单独触发与授权。
- CLI 前端继续显示 `Beta`；Woice 不变成聊天入口或 Agent 网关。
- 所有发行产物使用同一 Bundle ID；Core/Offline 模型清单和 SHA-256 可读回。
- 正式发行同时生成 `ReleaseManifest.json`：固定 Build、Bundle ID、Catalog URL/ID，以及 Core/Offline 文件名、大小和 SHA-256；上传后由独立门禁读回生产 manifest，并用 HTTPS HEAD 校验远程状态和 Content-Length。Catalog 另外读取响应体校验大小与 SHA-256；远程 DMG 不默认整包下载，摘要以发行服务读回的 manifest 字段与本地生成摘要比对。

### ReleaseManifest 读回契约

生产 manifest 在本地事实之上为 Catalog 和每个 DMG 增加 `status: "published"`、HTTPS `url`、`size` 和 `sha256`；远程 `buildVersion`、`bundleID`、文件名、Catalog URL/ID 必须与本地 `ReleaseManifest.json` 完全一致。`make release-verify-remote` 要求 Catalog GET 返回不超过 2 MiB 的 JSON，并比对实际大小/SHA-256；Core/Offline DMG 使用 HTTPS HEAD 校验 2xx 状态和 Content-Length，再比对发行服务读回的摘要与本地摘要。缺少 Content-Length、发生重定向、HTTP 非 2xx、状态非 `published` 或任一字段不一致均失败。

## 验收映射

| 计划条目 | 证据 |
|---|---|
| WCL-TAC-001～004 | `WorkspaceSidebarLayout` 几何/文本/路由策略测试与 `acceptance-workspace-sidebar` |
| WCL-TAC-005～008 | 音频分段、任务恢复、Provider fail-closed、媒体导入测试与既有 acceptance 命令 |
| WCL-TAC-009～013 | 权限状态策略、Agent 入站权限、可访问标签/AppIcon 静态门禁测试 |
| WCL-TAC-014～016 | `release-developer-id` 脚本的凭据检查、签名/公证/staple/本地 manifest 验证；`release-verify-remote` 读回生产 manifest 并校验 Catalog/远程产物状态、大小和摘要；无凭据或不一致时失败 |
| WCL-TAC-017～019 | Agent 权限策略、显式二次确认/无再派发入口的 fail-closed 边界、hop/重复/路径/输出限制与 CLI 状态测试 |

## 当前结果与关闭规则

- 本轮已逐条执行 `make docs-check`、`make harness-check`、`make lint`、`make test`、`make verify`；Native Host 权限下 `make verify` 通过 201 项 Swift 测试 / 13 个 Suite、PI/MCP、构建、lint、AppIcon 门禁、模型发行门禁和 Core 打包；Store 条件通过 179 项 Swift 测试 / 10 个 Suite。
- WCL-00～03、WCL-05 的源码和自动门禁已收口；真实会议、TCC、VoiceOver 和真实 CLI 账户仍是非开发提醒。
- WCL-04 的本地发行工程和远程读回代码已具备；只有在用户提供 Developer ID 身份、公证凭据、生产 Catalog 配置并发布远程 manifest/产物后，才能从“发行验证阻塞”改为完成。
- WCL-06 的正式 Store 账号、签名 Sandbox/TCC、模型/隐私审定、Archive、TestFlight 和审核仍未完成；MAS-03 本机能力裁剪、`project.yml`/`Woice.xcodeproj` 生成及 `Woice-Store / Release-AppStore` 无签名构建已在独立上架计划中记录，不把它们写成正式商店发布完成。
