# 实时文字预览、顶部面板收起与导入页优化

> 状态：代码与自动门禁完成；真实 Speech partial 和桌面手感只作人工提示
> 日期：2026-08-25
> 映射：WCL-08

## 目标

- 开启“录音时预览文字”后，录音期间在工作台和菜单栏 Popover 直接显示本机 partial transcript。
- 菜单栏 Popover 打开后，点击面板外任意位置立即收起，不必再点一次状态栏图标。
- 导入页使用更紧凑的原生层级，支持按钮选择和拖放文件，同屏说明支持格式与本机保存边界。

## 范围

- 复用 `AppState.liveTranscript` 和 `LiveTranscriptionState`，不新增第二条识别链路。
- 实时预览只在正在录音、已开启预览且录制麦克风时可见。
- 设置页将预览开关移出“高级录音选项”，并明确说明显示位置、本机处理和不覆盖最终原文。
- 导入后的“转文字 → 打开素材”既有流程不变。
- 不改变 Speech 权限、云端外发确认、Artifact 不可覆盖和模型路由语义。

## 非范围

- 不把实时预览保存为最终 Transcript。
- 不为纯电脑声音录制伪造实时文字。
- 不新增网络请求、云端降级、第三方依赖或数据 Schema。
- 不重设导入后的任务、模型安装或素材详情组件。

## 交互与文案

### 实时预览

- 准备权限/模型时显示“正在准备本机实时预览”。
- 正在识别但尚无文字时显示“正在听…”。
- 有 partial transcript 时显示最新文字；工作台允许更多行，Popover 限制高度。
- 本机 Speech 不可用时显示可执行原因，同时明确“录音仍会继续保存”。

### 导入页

- 主动作保留“选择文件…”，整个投放区可拖入单个文件。
- 可见格式：WAV、MP3、M4A、AAC、AIFF、CAF、FLAC、MP4、MOV、M4V。
- 显示“原件保存在本机，不会自动外发”；不增加许可勾选或额外确认。

## 验收标准

- 录音预览开关在“录音与转写”首层可见，不再藏于高级折叠区。
- 预览开关关闭、未选麦克风或未录音时，工作台和 Popover 均不显示空占位。
- `.requestingPermission`、`.listening`、`.unavailable` 状态有确定性标题、图标和正文；预览不改写最终原文。
- Popover 在本 App 内或其他 App 中点击面板外后收起；点击面板内控件不误收起。
- 导入 Sheet 默认高度收紧，按钮选择和拖放走同一个导入函数；不支持、空文件、损坏容器仍 fail-closed。
- 新增状态投影/收起策略测试，并通过 `swift test`、`make lint`、`make docs-check` 与 `make harness-check`。

## 影响面

- UI：`WorkspaceView`、`MenuBarPopover`、`SettingsView`、`MediaImportSheet`。
- AppKit 组合：`WoiceMenuBarController` 的应用内面板外鼠标监听、跨应用失去焦点通知与生命周期清理。
- 状态：仅读既有 `AppState` 实时转写投影。
- 存储、Provider、RPC、Agent、模型包和发行边界不变。
