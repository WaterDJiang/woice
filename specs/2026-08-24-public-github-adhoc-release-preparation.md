# 公开 GitHub 仓库与 ad hoc 预发布准备

> 状态：已完成；公开源码已推送，预发布 Asset 仍待单独上传  
> 日期：2026-08-24  
> 关联：[双版本分发与模型接入](../doc/spec/2026-08-22-dual-edition-model-integration.md) · [M2-08 模型接入与双版本发布](../doc/plan/2026-08-22-model-integration.md)  
> 替代：无  
> 保留：Core/Offline 使用同一 App、Bundle ID、数据目录和模型清单校验的既有语义  
> 迁移：预发布只产出 ad hoc DMG；Developer ID 签名、公证和正式 GitHub Release 仍由 M1-07/M2-08i 承接  
> 停止：不把 `.build`、`build`、模型权重、用户录音、数据库、证书或本地配置提交到公开仓库  
> 顺序：属于 R1 M2-08 的公开预发布准备，不解除 R0/R1 真实 Mac 发行验收门禁

## 目标

将 Woice 整理为可公开托管的 MIT 代码仓库，并在 Apple Silicon Mac 上稳定产出两份可校验的 ad hoc 预发布 DMG：

| 包 | 内容 | 目标用户 |
|---|---|---|
| `Woice-Core` | App 与模型管理能力；不含第三方模型权重 | 已有本机 ASR 服务或希望自行下载模型的用户 |
| `Woice-Offline` | 与 Core 相同的 App，加一个已校验的 WhisperKit 模型包 | 希望下载后离线完成首次转写的用户 |

## 范围

- 新增中文 README、MIT LICENSE 与公开仓库 `.gitignore`。
- README 明确 macOS 14+、Apple Silicon（`arm64`）是首批支持范围；不实现 Universal Intel 包。
- 新增 `make release-adhoc`：从同一 Release binary 打出 Core/Offline，强制 `WOICE_CODESIGN_IDENTITY=-`，校验架构、签名、DMG，并生成版本化 DMG 与 `SHA256SUMS.txt`。
- `Offline` 仍要求调用者显式传入 `WOICE_OFFLINE_MODEL_ROOT`；脚本只接受 manifest 校验通过的 WhisperKit 模型包。
- 在 `WaterDJiang/woice` 创建公开 GitHub 仓库，建立首个 `main` 提交并推送源码与文档。

## 非范围

- 不创建 GitHub Release 或上传 Release Asset；DMG 继续以已校验的本地预发布产物保留。
- 不执行 Developer ID 签名、Notarization、Stapling 或 Gatekeeper 通过性声明。
- 不将模型权重、用户数据或发布二进制纳入 Git。
- 不修改产品功能、模型默认路由或 Bundle ID。

## 验收标准

- AC-PG-001：README 说明产品定位、两个下载包、安装限制、隐私边界、构建与测试命令。
- AC-PG-002：根目录 LICENSE 为 MIT，README 不将第三方依赖或模型权重误称为 MIT。
- AC-PG-003：`.gitignore` 覆盖构建物、DMG/Release 输出、模型权重、本地录音/数据库、密钥/证书、环境文件与 Node 缓存；`Package.resolved`、源码、文档和受控测试 Fixture 不被误忽略。
- AC-PG-004：提供 `WOICE_OFFLINE_MODEL_ROOT=<已验证模型根目录> make release-adhoc`，输出 `release/<version>-<build>-arm64-adhoc/` 下的两份 DMG 和 SHA-256 清单。
- AC-PG-005：两份 DMG 的 App 均通过 `codesign --verify --deep --strict`；DMG 均通过 `hdiutil verify`；二进制仅含 `arm64`。
- AC-PG-006：预发布说明明确 ad hoc 包未公证，下载后出现 Gatekeeper 提示属于预期；不将该包描述为正式发行包。
