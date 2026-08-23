# M2-07 受控进程 Provider 运行时

> 状态：本轮实现；签名验证仍待发布工作包

## 1. 目标

在 Manifest 契约之上提供最小、可终止、输出受限的 stdin/stdout Provider 调用器，避免外部进程污染 Woice 主进程。

## 2. 范围

- 每次调用使用独立临时工作目录和固定环境白名单，不继承 API Key、Shell 环境或用户 Prompt。
- 请求通过 stdin 发送一份 JSON/Data，响应只读取 stdout；超过输出上限或超时立即终止。
- 可执行文件必须先通过 Manifest 校验并存在且可执行；拒绝被标记为 rejected/unknown 的 Provider。
- stderr 不返回给 Provider 业务结果，只作为脱敏诊断信息。

## 3. 不在本工作包

- 不验证代码签名、公证、沙箱 profile 或网络权限；这些属于发布门槛。
- 不把 Provider 结果自动写成 Artifact，不绕过 Runtime 的外发和用户确认策略。

## 4. 验收标准

- `/bin/cat` fixture 能完成受控 stdin/stdout 往返。
- 不存在/不可执行文件、拒绝信任状态、超时和超限输出均返回稳定错误。
- 临时工作目录调用结束后可清理；`make verify` 通过。
