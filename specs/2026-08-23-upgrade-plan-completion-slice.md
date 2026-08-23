# 升级计划完成切片：权限反馈、Catalog 发布与验收自动化

## 目标

继续收口当前升级计划中可以在本机稳定验证的缺口，避免把“代码可编译”误写成真实发布完成：

- 系统声音权限状态在用户授权后重新进入 Woice 时显示真实能力，不保留过时的“需要权限”。
- 设置页转写能力状态显示实际 Provider 名称、数据位置和传输方式。
- 模型 Catalog 支持已验证的静态载荷加载、信任根匹配、版本回滚保护；失败不得触发下载或安装。
- Core/Offline 产物具备可重复的本地 DMG 构建与 strict 校验入口；正式 Developer ID、公证仍需外部证书。
- 模型性能报告和素材/RPC/UI 验收入口能够明确报告“已通过、跳过或缺少真实环境”。

## 范围

- `Sources/WoiceApp/`：系统音频能力刷新、设置页显示修正。
- `Sources/WoiceCore/`：Catalog 信任与回滚契约。
- `scripts/`、`Makefile`：DMG、基准和验收命令。
- `Tests/`：纯契约、fail-closed 和脚本验证。
- `doc/plan/`、`doc/log/`：证据和未完成边界同步。

## 不在范围

- 不伪造 Apple TCC、真实休眠/拔设备、长录音、真实会议或生产 Developer ID/公证证据。
- 不把测试公钥写成生产信任根，不自动更新远程 Catalog。
- 不新增 Woice 自有 Agent 能力或内置 LLM 工作流。

## 验收标准

- TCC 能力刷新在 `scenePhase` 回到 active 和应用重新激活后重新读取 `SCShareableContent`；授权成功的运行时事实优先于旧的 preflight 缓存。
- 设置页能力行不显示字面量插值文本。
- Catalog 载荷必须通过 schema、签名、公钥 keyID、时间和单调版本检查；旧版本或错误信任根 fail-closed。
- `make package-dmg-core`、`make package-dmg-offline` 在有对应 App/模型输入时生成 DMG，并通过 `hdiutil verify`；没有输入时响亮失败。
- `make verify`、`make docs-check`、`make harness-check` 全部通过；文档明确记录外部证书和真实设备矩阵仍待验收。

