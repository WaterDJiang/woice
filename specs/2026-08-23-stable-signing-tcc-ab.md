# 稳定签名下 TCC A/B 覆盖安装规格

## 目标

验证 Woice 在同一 Apple Development 稳定身份下由 Build A 覆盖到 Build B 时，产品身份和权限声明保持不变，并为用户手动完成 TCC 连续性验收提供可复现路径。

## 范围

- 使用同一 `CFBundleIdentifier=com.woice.app`、Team ID、可执行文件名和权限相关 Info.plist。
- 只改变 `CFBundleVersion`，生成 Build A 与 Build B。
- A、B 都通过 `codesign --verify --deep --strict`，并记录签名身份、指定要求、权限声明和二进制 SHA-256。
- 覆盖安装前保留当前 `/Applications/Woice.app` 的可恢复备份；不重置 TCC、不删除用户素材、不修改 Keychain。
- 本轮不把真实录音、真实文件导入或真实会议声音测试自动化；这些由用户按手动路径验收。

## 非目标

- 不生成 Developer ID、公证或 Mac App Store 包。
- 不证明 ad hoc 到稳定签名的旧授权必然继承；该迁移必须由用户在系统设置中逐项确认。
- 不调用 `tccutil reset`，不代替用户点击系统权限弹窗。

## 验收标准

1. A/B 的 Bundle ID、Team ID、可执行文件名、关键权限声明和 designated requirement 一致。
2. A/B 的 Build Number 不同，版本内容和签名身份可追溯。
3. A 安装后启动工作台；B 覆盖安装后仍能启动同一工作台，用户素材目录不变。
4. 覆盖安装前后由用户手动检查麦克风、系统音频、语音识别、辅助功能四项权限；若系统要求重新授权，必须明确记录为迁移结果，不得标记为继承通过。
5. 安装与验收证据写入 `doc/log/2026-08-23.md`，未完成项继续保留在计划中。

## 手动 TCC 路径

### A：首次稳定签名安装

1. 启动 A，进入“设置 → 录音与输入/文件与隐私”。
2. 只点击“请求麦克风权限”，在系统弹窗选择允许；回到 Woice 点击“重新检查”。
3. 开启会议模式，按提示请求“屏幕与系统音频录制”，在系统设置中允许 Woice 后回到应用点击“重新检查”。
4. 选择 macOS Speech 本机转写时再处理语音识别权限；不提前索取。
5. 需要自动粘贴时才请求辅助功能；“复制原文”必须始终可用。
6. 截图记录四项权限的最终状态与 A 的 Build Number。

### B：覆盖安装连续性

1. 关闭 A 的工作台窗口，确认 Woice 进程已退出，再安装 B；不要删除 `~/Library/Application Support/Woice`。
2. 启动 B，确认素材数量、最近素材、设置草稿和当前模型选择保持不变。
3. 逐项点击“重新检查”，记录麦克风、系统音频、Speech、辅助功能是否保持“已授权”。
4. 若任一项变为“需要授权/需要重新授权”，按系统设置重新允许，再回到 Woice 刷新；这属于稳定签名迁移后的重新授权，不是 A/B 继承通过。
5. 只验证 UI 状态、录音按钮可用性和权限诊断；真实录音、真实文件导入和会议声音留作用户手动测试。

## 证据文件

- A/B 包及 `manifest.json`：脚本输出目录。
- 当前安装包备份：脚本输出目录中的 `Woice-before-stable-ab.app`。
- 命令输出：`codesign -dvv`、`codesign -r-`、`codesign --verify` 和 SHA-256。
- 用户截图与手动结果：追加到 `doc/log/2026-08-23.md`。
