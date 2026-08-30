# 前端显示产品版本号

## 目标

在 Woice 主工作台的可见导航区域显示当前 App 的产品版本号和 Build，方便用户确认安装包版本与反馈问题。

## 范围

- 从当前 Bundle 的 `CFBundleShortVersionString` 和 `CFBundleVersion` 读取版本信息。
- 工作台侧栏导航副标题显示 `工作台 · v<版本> (<Build>)`。
- 设置页“文件与隐私”中的版本字段继续保留，并复用同一版本信息来源。
- 缺少 Bundle 字段时使用安全的“开发版”回退，不阻塞 App 启动。

## 不变约束

- 不在 Swift 源码中硬编码发布版本；版本仍由 `Resources/Info.plist` 和构建配置提供。
- 不改变 Bundle Identifier、签名、模型、存储或设置保存行为。
- 版本展示只读，不新增设置字段或持久化数据。

## 验收标准

- AC-001：打开 Woice 工作台时，侧栏导航标题下可见产品版本和 Build。
- AC-002：设置 → 文件与隐私仍显示相同的版本与 Build。
- AC-003：Bundle 字段缺失时显示开发版回退，且不会崩溃。
- AC-004：`make test`、`make lint` 和 `make verify` 通过。

