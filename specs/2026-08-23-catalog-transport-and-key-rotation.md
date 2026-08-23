# M2-08d Catalog 传输、密钥轮换与撤销规格

## 目标

在已有 Ed25519 Catalog 验签和本地回滚保护之上，补齐“用户主动更新”的安全边界：

- 只允许显式调用的 HTTPS Catalog 拉取，不在启动、录音或打开设置时自动联网。
- 请求目标使用构建时 allowlist；不接受任意公网地址、明文 HTTP、用户信息或跨域重定向。
- Catalog 的模型条目先完成签名验证和版本检查，再交给模型下载器；失败不改变当前库存。
- 支持由当前受信签名者声明下一把公钥和撤销旧公钥；轮换历史必须可验证，不能只信任可被本地改写的 key map。

## 契约

- `ModelCatalog.keyRotation` 是签名覆盖的一部分，包含新增公钥和撤销 key ID。
- 新增公钥必须是 32 字节 Ed25519 公钥，key ID 不可重复；撤销项必须来自当前信任集合或同一轮新增集合。
- 接受一份 Catalog 前，Store 从内置 trust roots 开始，按持久化的已签名 Catalog 历史逐项重放签名与轮换；历史缺失、乱序、回退或签名无法由当前集合验证时 fail-closed。
- 同一 `catalogVersion` 的 unsigned payload 不允许变化；更低版本拒绝；新版本通过后才原子写入历史快照。
- 轮换后至少保留一把未撤销的受信公钥；签名者可在同一轮自我撤销，但必须同时带来可用的新签名者。

## 传输策略

- `ModelCatalogFetcher` 只接受 HTTPS、明确 host allowlist、无用户名/密码、响应不超过 2 MiB、超时不超过 10 秒。
- 不发送 API Key、Cookie 或录音/转录内容；只发送 `Accept: application/json`。
- HTTP 非 2xx、内容超限、非 JSON 或 URL 不符合策略时返回稳定错误，不触碰 Catalog Store。
- 该 Fetcher 不负责定时任务、重试、下载模型或 UI；调用方必须在用户动作后显式触发。
- Woice 设置页提供显式“检查更新”入口；发行包没有配置 `WOICEModelCatalogURL`、`WOICEModelCatalogID` 和 `WOICEModelCatalogTrustedKeys` 时，入口保持禁用且不会联网。
- 模型文件下载 host 使用独立的 `WOICEModelDownloadAllowedHosts` allowlist；未配置时仅继承 Catalog host，不允许通过条目 URL 临时扩大信任范围。

## 验收

- URL policy 拒绝 HTTP、公网未 allowlist、用户名密码和超限响应；合规 HTTPS 请求只发送 GET/Accept。
- 已签名 Catalog 可以通过远程 bytes 进入 Store；篡改、回退、同版本分叉、未知 key、撤销 key 和轮换历史缺失均拒绝。
- 轮换后的新 key 可以签署下一版本；被撤销的旧 key 无法继续签署；重启后从快照恢复同样的信任状态。
- 所有失败不改变当前 Catalog、模型库存和录音/转写状态。
