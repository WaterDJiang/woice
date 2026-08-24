# Markdown 导出目录快捷键编辑

> 状态：已实现；稳定签名 Build `2026082408` 运行态快捷键验证通过

## 目标

- 让“文件与隐私 → Markdown 导出目录”使用 macOS 原生文本编辑快捷键。
- 保持目录修改只进入当前设置草稿，仍由“保存本页”独立提交。

## 范围

- 为应用主菜单补齐标准“编辑”菜单：撤销、重做、剪切、拷贝、粘贴、删除和全选。
- 让设置页中的目录输入框继续使用原生 `TextField`，由第一响应者处理编辑命令。
- 保留文件分区的独立保存、还原和 Keychain 隔离行为。

## 不在本轮

- 不改变导出目录解析、默认目录或已有导出文件格式。
- 不把目录修改即时写入设置，不新增 Keychain 访问。
- 不引入自定义文本编辑器或覆盖 macOS 原生快捷键。

## 验收标准

- AC-001：目录输入框获得焦点后，⌘A 可全选，⌘C/⌘X/⌘V 和 Delete 可编辑当前草稿。
- AC-002：应用菜单栏显示“编辑”菜单，菜单命令作用于当前第一响应者，不抢占文本框快捷键。
- AC-003：修改目录后只显示本页未保存状态；“还原本页”可恢复原值，“保存本页”才持久化。
- AC-004：保存或还原文件分区不读取、不写入、不删除 API Key；导出路径解析行为和默认目录保持不变。
- AC-005：`make format`、`make test`、`make verify`、`make docs-check` 和 `make harness-check` 通过。

## 影响面

- `Sources/WoiceApp/WoiceApp.swift`
- `Sources/WoiceApp/SettingsView.swift`
- `specs/2026-08-24-markdown-export-directory-editing.md`
- `doc/log/2026-08-24.md`
- `doc/log/INDEX.md`
