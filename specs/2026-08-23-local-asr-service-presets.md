# 本机 ASR 服务预设规格

> 状态：代码与自动门禁完成；真实第三方本机服务连接仍待用户验收
> 日期：2026-08-23
> 替代：无；补齐 M2-08f 本机服务连接向导的预设缺口
> 保留：现有 OpenAI-compatible HTTP 客户端、主动模型发现和用户确认外发边界
> 迁移：预设只负责填入设置草稿；实际 Endpoint、模型、Key 和保存仍由用户控制
> 停止：不自动安装/启动 whisper.cpp、faster-whisper、FunASR 或 LocalAI，不自动扫描端口，不把预设当作服务已就绪
> 顺序：选择预设 -> 填写/确认地址与模型 -> 保存草稿 -> 用户主动健康检查或模型发现

## 目标

- 为常见本机 OpenAI-compatible ASR 服务提供可理解的起点，减少手填协议和模型字段的负担。
- 预设目录只包含稳定 UI 文案、常见本机地址、模型占位和协议说明，不包含凭据或进程路径。
- 预设应用到 `SettingsView` 的草稿，不立即修改运行时路由；保存仍遵循现有独立 Keychain 写入规则。

## 首批预设

- 通用 OpenAI-compatible：`http://127.0.0.1:8000/v1`，模型 `whisper-1`。
- whisper.cpp Server（OpenAI-compatible）：`http://127.0.0.1:8080/v1`，模型 `whisper-1`。
- faster-whisper Server（OpenAI-compatible）：`http://127.0.0.1:8000/v1`，模型 `whisper-1`。
- FunASR / LocalAI（OpenAI-compatible）：`http://127.0.0.1:8080/v1`，模型 `whisper-1`。

地址和模型都是可编辑初始值；服务是否存在、协议是否兼容必须由用户点击健康检查确认。所有首批地址均为 loopback，允许模型发现但不会在选择预设时发请求。

## 验收标准

- 预设 ID 唯一、地址为 loopback HTTP(S)，不含凭据、query 或 fragment。
- 选择预设只改变草稿；未点击“保存设置”前，AppState 当前路由和 Keychain 不变。
- 选择预设不触发网络请求、权限请求、模型下载或进程启动。
- 预设文案明确“OpenAI-compatible”兼容前提，不能把服务显示为已连接。
- `make test`、`make verify`、`make docs-check`、`make harness-check` 通过。
