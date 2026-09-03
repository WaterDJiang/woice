# 模型清单 Raw 响应类型兼容修复

> 状态：待实现
> 日期：2026-09-03

## 问题

App Review 在 macOS 26.6.1、联网环境点击“检查更新”时看到错误。实测固定的 GitHub Raw 地址返回 `200`，正文为合法 JSON，但响应头为 `Content-Type: text/plain; charset=utf-8`。当前 `ModelCatalogFetcher` 只接受 `application/json` 或 `+json`，因此在签名验签前错误拒绝响应。

## 目标

- 允许固定 HTTPS 模型清单地址返回的 `text/plain` JSON 响应进入现有解析链路。
- 继续由 `ModelCatalogStore` 执行 JSON schema、Catalog ID、版本、信任历史和 Ed25519 签名校验。
- 不扩大模型下载 host allowlist，不改变模型下载和本机转写边界。

## 范围

- 修改 `ModelCatalogFetcher` 的响应类型门禁。
- 新增回归测试，覆盖 GitHub Raw 的 `text/plain; charset=utf-8` 和仍应拒绝的非文本非 JSON 类型。
- 更新文档索引与执行日志。

## 验收标准

- GitHub Raw `200 + text/plain; charset=utf-8` 的 JSON 正文可以继续进入 Catalog 验证。
- `application/json`、`application/*+json` 继续通过。
- `text/html`、图片或其他明确非 JSON 类型继续 fail-closed。
- `make test`、`make verify-app-store`、`make docs-check`、`make harness-check` 通过。
- 不读取或修改用户录音、数据库、Keychain、模型文件和签名材料。

## 影响面

- 只影响用户主动点击“检查更新”的模型 Catalog 获取。
- 不影响录音、复听、已安装模型、Qwen 推理或外部 ASR。
