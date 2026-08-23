# M2 核心验收 Harness

## 目标

把用户当前明确验收目标固化为一条可重复命令：真实麦克风有非零输入、录音可经本机 ASR 最小 Adapter 或 loopback OpenAI-compatible ASR 返回原文、PCM 时长可信、详情页播放器能预加载并复听。

## 命令

在已授权麦克风的真实 Mac 上运行：

    make acceptance-core

该命令只向 127.0.0.1 发送测试 ASR 请求，不读取或写入真实用户录音目录，不使用真实 API Key。

## 验收范围

- 麦克风输入自检返回非零音频帧和峰值。
- AppState 真实录音固化 WAV，经过用户确认语义的 loopback ASR 请求保存原文。
- AppState 真实录音在无外部 Endpoint 时走本机 ASR 路由，并持久化模型版本快照；验收使用无隐私 Fake Provider，不把它当作真实语音识别准确率。
- 自定义 ASR 的 verbose_json 时间戳片段写入录音记录，并可用于详情页定位回听。
- 录音时长与已写入 PCM 帧一致，误差门槛为 20 ms。
- 播放器能读取已提交 WAV 的总时长、保持未自动播放并支持回放/跳转。

## 非目标

- 不替代真实第三方 ASR 网络、识别准确率、系统音频 CAF 或 Developer ID/公证验收。
- 系统音频严格测试继续使用 WOICE_REQUIRE_SYSTEM_AUDIO=1 单独运行，失败必须显式报告。
