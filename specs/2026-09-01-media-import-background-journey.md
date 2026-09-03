# 导入转写后台继续真实桌面验收规格

## 目标

为 `MRQ-UX-01` 提供可重复的隔离桌面 Journey，验证导入素材点击“转文字”后，用户关闭浮窗不会取消已经持久化的转写任务，工作台仍可继续操作，任务最终仍能写入原文。

## 范围

- 仅覆盖 `Woice (Dev).app` 的测试模式和临时 Workspace。
- Fixture Provider 增加显式、仅测试模式可用的转写延迟，让验收可以在任务处于“正在转写”时点击关闭。
- `acceptance_media_import_desktop.sh` 在测试模式导入后自动启动 Fixture 转写并呈现运行中的 Sheet，确认“关闭并后台继续”可见并执行，再确认工作台窗口仍存在、任务最终完成且原件/派生音频/原文均持久化。
- 测试模式导入等待素材详情 hydrate 完成后再写入临时 Workspace，避免故意触发正式运行时的全量变更 fail-closed 门禁。
- 测试结束清理临时 Workspace；不读取、修改或删除用户正式素材、正式数据库、Keychain 或 TCC。

## 非目标

- 不改变正式 Provider 的转写调度、取消语义或 UI 文案。
- 不用延迟 Fixture 证明真实模型速度、音频质量或 TCC 连续性。
- 不通过自动脚本代替真实用户对关闭后的视觉手感判断；脚本只提供状态和持久化事实证据。

## 验收标准

- `WOICE_TEST_TRANSCRIPTION_DELAY_SECONDS` 只在 `--woice-test-mode` 且 Fixture Provider 下生效，非测试启动不会读取该配置。
- 桌面 Journey 在转写运行时能观察到“关闭并后台继续”，点击后浮窗消失但 `Woice 工作台` 窗口仍可见。
- 关闭后不出现取消状态；临时 Workspace 最终包含原始 `.source.*`、派生 `.wav` 和完成的转写原文。
- 测试失败时输出原始日志、窗口状态和临时证据路径；成功时明确记录 `closed_background=1`。

## 验证命令

```bash
WOICE_RUN_MEDIA_IMPORT_JOURNEY=1 \
WOICE_MEDIA_IMPORT_SOURCE=/path/to/fixture.wav \
make acceptance-media-import-desktop
```
