# Woice

> 本地优先的 macOS 语音素材采集器。录音、转写、复听和素材库是核心；外部 Agent 只在素材完成后、经授权读取上下文。

Woice 帮你把主动录下的声音变成可复听、可搜索、可导出的素材。原始音频和原始转录不会被原位覆盖；重转写和编辑会形成可追溯的新版本。

## 预发布下载包

首个公开预发布只支持 **macOS 14+ 与 Apple Silicon（arm64）**。

| 下载包 | 是否包含第三方模型权重 | 适合谁 |
|---|---|---|
| `Woice-Core-…-arm64.dmg` | 否 | 希望下载体积更小，安装后再从 App 内一键下载任一支持模型的用户 |
| `Woice-Offline-…-arm64.dmg` | 是，v0.1.3 包含已校验的 Qwen3-ASR-0.6B 4-bit 本机模型 | 希望下载后直接离线转写的 Apple Silicon 用户 |

两个包使用同一 App、数据目录和功能集；Offline 仅多出一个随包模型。切换安装包不会删除你的录音、已下载模型或设置。

### 可用的语音转文字方式

v0.1.3 不只支持 Qwen。Offline 为了控制体积，只预先放入 Qwen 权重；Core 不带任何第三方权重。安装 Core 后，用户可以直接在 App 的模型列表中选择 WhisperKit Tiny、Qwen3-ASR-0.6B 4-bit 或 WhisperKit Large-v3，点击一次即可下载、校验和安装，不需要手动配置路径或运行时。

| 转写方式 | v0.1.3 是否支持 | Offline 是否随包 | 如何获取 |
|---|---|---|---|
| macOS 本机语音识别 | 是 | 系统提供，无第三方权重 | 无需下载 |
| WhisperKit Tiny | 是 | 否 | Core / Offline 均可在模型列表一键下载 |
| Qwen3-ASR-0.6B 4-bit | 是 | 是 | Offline 直接使用；Core 可在模型列表一键下载 |
| WhisperKit Large-v3 | 是 | 否 | Core / Offline 均可在模型列表一键下载 |
| OpenAI-compatible ASR | 是 | 否 | 用户主动配置本机、局域网或云端服务 |

当前 GitHub 下载包采用 **ad hoc 签名，未公证**。下载后 macOS 可能提示“无法验证开发者”；请仅从本项目的 GitHub Release 下载，并在 Finder 中按住 Control 点击 App 后选择“打开”。正式 Developer ID 签名和公证尚未完成。

### TestFlight / App Store 版本

`0.1.4 (Build 5)` 使用签名模型 Catalog 提供按需下载。Catalog 会先由 App 验证 Ed25519 签名，再允许逐文件下载、校验和安装。模型权重不随 Store 包上传；首次打开且没有模型时，工作台会明确提示先下载语音转换模型。推荐策略为低于 16 GiB 选择 Tiny、16～31 GiB 选择 Qwen3-ASR 0.6B、32 GiB 及以上选择 Large-v3；目标模型尚未进入线上签名 Catalog 时会安全回退到可下载模型。下载必须由用户点击确认。

## 产品边界

- 录音只能由用户的按钮、快捷键或已明确授权的连接器触发。
- 本机处理失败不会自动将音频或文字发送到云端；每个云端目标首次外发前都需要单独授权。
- 没有模型时，Woice 仍会安全保存录音并提示下一步，不会伪装成已转写成功。
- 外部 Agent 不能直接读取数据库、音频设备、Keychain 或任意本地目录。

## 从源码构建

前置条件：macOS 14+、Apple Silicon、Xcode 16.4+、Swift 6.1、`swift-format`，以及 Node.js（用于 Connector 测试）。

```bash
make project
make build
make test
make verify
```

常用检查：

```bash
make docs-check
make harness-check
make lint
```

## 构建 ad hoc 预发布 DMG

离线包只接受已验证的本机模型目录；路径必须由调用者显式指定。

```bash
WOICE_OFFLINE_MODEL_ROOT="/Users/your-name/Library/Application Support/Woice" make release-adhoc
```

命令会在 `release/<version>-<build>-arm64-adhoc/` 生成：

- `Woice-Core-<version>-<build>-arm64.dmg`
- `Woice-Offline-<version>-<build>-arm64.dmg`
- `SHA256SUMS.txt`

构建过程强制使用 ad hoc 签名、验证每个 App Bundle 与 DMG，并确认二进制只有 `arm64`。这些产物刻意被 Git 忽略；将 DMG 和校验清单作为 GitHub 的预发布 Asset 上传，而不是提交进仓库。

## 项目结构

```text
Sources/WoiceCore/  领域模型、Provider/RPC 契约与稳定错误语义
Sources/WoiceApp/   SwiftUI/AppKit、录音、存储、模型和组合根
Tests/              单元、集成与契约测试
Connectors/         仅经 Woice RPC 访问素材的薄适配层
Resources/          App 元数据、Notices
scripts/            打包与真实 Mac 验收脚本
doc/                规格、计划、设计与执行日志
```

更多入口见 [doc/INDEX.md](doc/INDEX.md)。

## 许可与第三方内容

本仓库的 Woice 源码使用 [MIT License](LICENSE)。第三方依赖、品牌素材和模型权重不因而自动改为 MIT：它们分别保留各自的许可证、Notice 与来源说明。模型权重不会提交到本仓库；Offline DMG 会在其 App Bundle 内携带该模型的清单与许可证信息。

## 贡献与安全

提交前运行 `make verify`。不要提交录音、转录、SQLite 数据库、模型权重、API Key、证书或本地环境文件；根目录 `.gitignore` 已覆盖这些常见路径，但提交前仍请复核暂存内容。
