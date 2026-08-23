# 自定义 ASR 回环 HTTP 验收夹具

> 状态：基础验收完成；仅用于本机测试，不是生产 Provider。

## 目标

用真实 `URLSession` 和 loopback HTTP 服务验证自定义 OpenAI-compatible ASR 配置，而不是只依赖 `URLProtocol` 替身。

## 约束

- 服务只监听 `127.0.0.1` 的临时端口，测试结束立即关闭。
- 请求必须包含 `/audio/transcriptions` 路径、WAV multipart、模型、语言和 Bearer 头。
- 响应使用 OpenAI-compatible JSON；不连接互联网、不使用真实 API Key、不写入用户工作区。

## 验收标准

- `TranscriptionClient` 通过真实 `URLSession` 从 loopback 服务得到原文。
- 在已授权的真实麦克风上，`AppState` 能完成录音、停止固化、等待外发确认、请求 loopback ASR、保存原文，并从同一 WAV 加载播放器与跳转位置。
- 夹具能观察并断言请求路径、授权头、模型、语言和 `RIFF` WAV 内容。
- 原有 `make verify`、真实麦克风和 AppState ASR smoke 不回归。
