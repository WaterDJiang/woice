# Qwen 推荐 Catalog 与 Dev / Store 0.1.4 发布规格

> 状态：实施中（Catalog 发布私钥阻塞）  
> 日期：2026-08-31  
> 关联规格：[本机模型一键安装与 App Store 兼容](2026-08-25-one-click-model-installation-and-store-compatibility.md)

## 目标

- 发布 `0.1.4 (Build 4)`，包含 Tiny、Qwen3-ASR 0.6B、Large-v3 三档内存推荐和模型库存去重。
- 本地使用 Apple Development 稳定签名生成并安装 `Woice (Dev).app`，只访问 Dev 数据、Keychain、锁和 Socket。
- Store Archive 使用 `Woice.app` / `com.water.woice`，安装包不携带模型；上传 App Store Connect。
- 模型 Catalog 升至 v2，使用既有 Ed25519 发布信任根签名，加入 Qwen 固定 revision 与逐文件 HTTPS 下载地址，再推送到 `main`。

## 范围边界

- Dev App 不上传；Store App 不使用 Dev 数据或 Bundle ID。
- 不提交或展示证书名称、Team ID、私钥、Provisioning Profile、钥匙串文件或账号凭据。
- 不生成新 Catalog 信任根替代旧密钥；既有发布私钥不可用时停止 Catalog 与线上发布。
- 不把 App Store Connect 接收构建写成已经审核或公开上架；审核状态以 Apple 返回为准。
- 保留用户录音、转录、数据库、已下载模型和正式版 App；旧 Dev App 只按 Harness 规则可恢复清理。

## 验收标准

- `make verify`、正式 Store Target、Store Bundle 无模型门禁和签名 Catalog 验签通过。
- Catalog v2 恰好包含 Tiny、Qwen3-ASR、Large-v3，Qwen 为 Apache-2.0、in-process、Store-compatible，所有文件有 HTTPS URL 和固定 SHA-256。
- `/Applications/Woice (Dev).app` 为 `0.1.4 (Build 4)`、`com.woice.app`、`WOICEAppChannel=dev`，严格签名验证通过。
- Store Archive 为 `0.1.4 (Build 4)`、`com.water.woice`、`WOICEAppChannel=store`，严格签名验证通过且无模型目录。
- Git 只提交本次相关源码、测试、公开 Catalog 与文档；不纳入无关工作区改动或本机敏感材料。
- GitHub `main` 回读包含提交，Catalog URL 回读摘要与本地一致，App Store Connect 上传工具返回成功。

## 当前发布状态

- 已完成：源码、测试与发行清单升至 `0.1.4 (Build 4)`；完整 `make verify`、Store Target 和 Store 无模型门禁通过。
- 已完成：Apple Development 稳定签名的 `/Applications/Woice (Dev).app` 已安装、严格验签、启动并确认使用独立 `Woice Dev` 数据目录。
- 已完成：Xcode 自动签名生成 Store Archive，身份、版本、渠道和无模型目录检查通过；导出阶段已生成 `Woice.pkg`，安装器签名链验证为 trusted。
- 说明：Archive 内部叶子签名的本机严格验签返回 `CSSMERR_TP_NOT_TRUSTED`，旧 Build 3 Archive 在当前钥匙串下结果相同；最终发行签名以导出的 trusted 安装器包为准。
- 阻塞：既有 Catalog Ed25519 私钥未在环境变量或已知项目路径找到，不能签发包含 Qwen 的 v2 Catalog；按本规格不得静默生成新信任根。
- 未执行：Git 提交/推送、Catalog 远程回读与 App Store Connect 上传，避免发布缺少 Qwen 的 Catalog。
