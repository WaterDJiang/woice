# M2-08d Catalog 模型多文件下载编排

> 状态：契约、签名校验与本机多文件下载门禁完成；生产 Catalog 服务验收待完成
> 替代：无；补齐现有 M2-08d 的 Catalog 条目消费边界
> 保留：`ModelCatalogStore` 的签名、回滚和密钥轮换门禁；`ModelPackDownloadCoordinator` 的 Range 续传与原子安装；WhisperKit 固定 revision 安装器作为开发/兼容路径
> 迁移：模型下载入口逐步从硬编码模型枚举迁移到“已验证 Catalog 条目 + 受控下载根地址”；旧入口在没有生产 Catalog 时继续可用
> 停止：未经 Catalog 验证的远程 manifest、任意用户输入 URL、下载后直接替换当前 Provider
> 顺序：Catalog Store 验证 -> 条目解析 -> 多文件下载 -> SHA-256/原子安装 -> 显式切换 Provider

## 目标

让一份已经通过签名、版本和信任历史校验的 `ModelCatalog` 能被用户显式选择，并把条目中的多个模型文件下载到可恢复 staging 目录，完成逐文件校验后再原子安装。下载失败、取消、重启或某个文件损坏时，当前模型、录音和已有转写保持不变。

## 契约

- `ModelPackManifest` 可携带 `downloadBaseURL`；它属于签名 payload，缺失时不能进入 Catalog 下载路径。
- 运行时只接受 HTTPS、无用户信息的下载根地址，并要求 host 命中发行包 `WOICEModelDownloadAllowedHosts`（未配置时继承 Catalog host）allowlist；不得由 UI 或文本框提供下载地址。
- 每个文件只允许使用 manifest 的安全相对路径；禁止路径穿越、符号链接和跨根目录 URL。
- `ModelPackDownloadCoordinator` 按 manifest 文件顺序逐个下载，已有完整文件跳过，部分文件使用 Range 续传；所有文件完成后由 `ModelPackStore.install` 做 SHA-256、字节数和原子 current 指针提交。
- Catalog 下载必须是显式用户动作；启动、录音、打开设置和刷新库存不能触发网络模型下载。
- 安装成功后才允许更新本机 Provider；下载中、暂停、失败状态不能改变当前 Provider。
- 一次只运行一个模型安装任务；Tiny/Large 不得因刷新或重复点击而并发下载。

## 验收

- 签名 Catalog 条目能解析出下载根地址和 manifest，按多文件 fixture 完成安装。
- 伪造 manifest、未 allowlist host、HTTP、用户信息、路径穿越、缺文件、大小或 SHA-256 不匹配均 fail-closed。
- 取消后 staging 保留，下一次显式继续能使用 Range；安装前库存不出现半成品。
- 同一条目重复点击不会创建第二个活动任务；已安装条目不会再次下载。
- Catalog 下载失败不改变当前模型选择、录音记录、转写任务或 Catalog 快照。
