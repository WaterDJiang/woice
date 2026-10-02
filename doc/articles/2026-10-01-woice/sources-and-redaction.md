# Woice 公众号稿：核对与脱敏说明

核对日期：2026-10-01；国内方案增补核对：2026-10-02（Asia/Shanghai）。状态：本地可编辑稿，未写入公众号后台、未发布。

## 当前编辑：精简正文链接

- 按用户要求将正文外部链接从 27 条减到 7 条：文末保留 Woice App Store／GitHub 两个必要入口，以及集中排列的五个官方价格参考。
- 删除段落末尾反复出现的产品、功能、隐私、下载和许可证链接；事实、价格核对日期、限定条件与七张配图保留。完整出处继续保存于本文件，不再把全部核对链接插入阅读正文。
- 当前图文包为 `/private/tmp/woice-wechat-2026-10-02-concise-links.zip`，旧包作为历史快照保留。

## 2026-10-02：按用户修订聚焦录音收费与硬件

- 当前正文已移除千问办公个人套餐、文档／写作／办公积分与钉钉任务协同等无关比较；也精简了苹果语音备忘录与 Aiko 的旁支介绍。此前调研记录仅作历史依据，不再代表当前正文选材。
- 千问按用户提供的当前使用情况写“目前还有免费额度”，不承诺具体分钟数或永久免费。官网可核定录音纪要入口，但本次未找到完整官方免费配额表；免费额度表述来自用户反馈，不冒充官方套餐核验。后续“可能调整额度或收费”是可能性判断，不是平台已经宣布的安排。
- 增加 GetSeed 与 PLAUD Note 的录音硬件费用对比。区分购机、赠送会员、到期后的录音与转写权益；没有把会员到期描述成硬件无法录音。
- 继续实际调用 `byted-web-search`，检索 GetSeed 官方帮助、录音卡会员及 PLAUD 硬件与转写套餐，再读取官方网页正文。第三方 GetSeed 699／888／999 元等不同套装／首发价格和 PLAUD 中国区历史价格未作为当前售价。GetSeed 当前购机价以官方商城套装为准，PLAUD 数字明确采用国际官网美元口径。
- GetSeed 官方会员页同时列早鸟 299 元与正价 399 元，并列明普通会员早鸟于 2026-06-30 结束，因此正文只采用“官方文档列正价 399 元/年”，不冒充实时下单价。专家版写作服务与价格不进入正文。
- 补读官方 FAQ 的 `python3` HTTP 请求在沙箱中失败，原错误 `Failed to resolve 'doc.biji.com'`；改用网页工具已读到同一官方正文，无需重复请求或更改依赖。

| 此次官方来源 | 采用的录音事实 |
|---|---|
| [GetSeed 官方介绍](https://doc.biji.com/docs/IxLiw9qxzisOFhkx9kFcFQRSnFc) | 实体开关、重点标记、独立离线录音、录完再同步；未声称实测录音质量优于软件 |
| [GetSeed 录音卡 FAQ](https://doc.biji.com/docs/G2NRwFLDYiE14ukO2rScezs7nAf) | 会员到期可继续录音；非会员每月 600 分钟转写；会员硬件转写不限时；转写要上传云端；不支持 USB 直接连接电脑管理文件 |
| [得到大脑会员权益](https://doc.biji.com/docs/AyPewORJhirCEzkuiBWcvCBfn0c) | 官方文档列普通会员正价 399 元/年，硬件转写不限时；与限时早鸟和专家写作会员区分 |
| [PLAUD Note 国际商品页](https://www.plaud.ai/products/plaud-note-ai-voice-recorder) | 159 美元购机、实体按键、包含每月 300 分钟免费转写；不套用为中国区价格 |
| [PLAUD 国际转写套餐](https://www.plaud.ai/pages/plaud-ai-plan-pricing) | Pro 年付 99.99 美元、1,200 分钟/月；Unlimited 年付 239.99 美元、转写不限时 |

每月 20 小时等于 1,200 分钟是显式假设的用量计算，不是作者真实使用记录。硬件购机、充电和同步的负担，以及现场采集与 Mac 线上录音的场景差异，是基于上述功能路线的取舍分析；未做设备实测或识别准确率排名。原有七张图、作者图、封面标题与开源／App Store 入口沿用。

当前稿验证：`make docs-check` 返回 `docs-check: ok`，限定本次文档的 `git diff --check` 通过；正文无千问办公／QwenWork／办公积分等已移除内容，七条图片引用有效且不重复，图片哈希与标题清单一致，作者图末尾仅出现一次、字节与原素材相同。当前交付 ZIP 为 `/private/tmp/woice-wechat-2026-10-02-recording-hardware.zip`，包含 16 个文件；旧图文包作为历史快照保留。

## 历史：2026-10-02 国内纪要方案与收费增补（后续已调整选材）

- 用户要求加入国内“妙计、千问”一类工具；产品名按飞书官方名称写为“妙记”。保留用户改过的标题《一段 AI 录音的成本，不只是转写费》，以及作者因收费与本机需求开始制作产品的动机；将“各大工具都开始收费”收窄为“一些工具按额度或订阅收费”。
- 实际使用用户指定的 `byted-web-search`。执行脚本为 `/Users/water/.agents/skills/byted-web-search/scripts/web_search.py`，检索飞书妙记／AI 会员、千问 App 录音纪要、千问办公个人套餐，再用官方来源核对。沙箱首次 DNS 错误为 `Failed to resolve 'open.feedcoopapi.com'`；允许联网后的同一脚本返回成功。依赖版本警告未影响本次搜索结果，未更改环境依赖。
- 区分三种入口：飞书妙记与智能纪要；千问官网录音纪要／实时记录；千问办公个人版 QwenWork。没有把千问办公 98 元／198 元月付价格套到千问 App 录音功能，也没有拿通义听悟开发者 API 促销价冒充个人纪要价格。
- 千问 App 录音纪要的专属收费、免费分钟和单次上限：本次没有核到可直接引用的官方公开价目，正文明确保留未知；不采用第三方“无限免费”或笼统会员收费推断。
- 飞书部分区分语音转写分钟与 AI 点数。当前会员帮助文档采用点数口径，旧智能会议宣传页仍展示“50 篇/月”等篇数套餐；正文不混用两套额度。功能介绍可引用该宣传页，价格和消耗规则使用当前会员页与帮助中心。
- 千问办公新用户赠分、登录赠分标注为“当前限时”；连续包月价格与单月购买价格分别写出，不把积分换算成录音分钟。不将可读取本地文件、断网录音或安装客户端推断为本机离线转写。
- 对比覆盖成本、便捷和内容去向；保留飞书团队协作与千问后续办公任务的价值，不宣称 Woice 准确率更高或云端产品必然泄露。

| 官方来源 | 此次采用的事实 |
|---|---|
| [飞书生成妙记](https://www.feishu.cn/hc/zh-CN/articles/386045971891) | 基础版每人每月 300 分钟转写；会议录制、手机录音、上传文件等入口；手机录音结束后上传；企业存储限制 |
| [飞书 AI 会员价格](https://www.feishu.cn/service/ai?tab=personal) | AI 会员 69 元/月、3,000 转写分钟；Plus 入门档 138 元/月、6,000 分钟 |
| [飞书 AI 会员权益消耗规则](https://www.feishu.cn/hc/zh-CN/articles/082024280492) | AI 会员 1,000 点/月、3,000 转写分钟/月；智能纪要通常 0.5 点/分钟，AI 额度与其他功能共享。正文 60 分钟消耗 30 点是按此标准计算的示例 |
| [飞书商业版与企业版](https://www.feishu.cn/hc/zh-CN/articles/255316448091) | 转写与企业存储权益；提示先查已有公司套餐，未把转写不限额度等同于 AI 纪要不限额度 |
| [飞书智能会议](https://www.feishu.cn/ai_meeting_trial) | 逐字稿、音视频上传、会议重点和待办的功能说明；未采用其旧篇数套餐计费 |
| [千问官网](https://www.qianwen.com/) / [实时记录](https://www.qianwen.com/live/) | 官方录音纪要／实时记录入口与转写、纪要定位；未核定专属价格 |
| [千问办公个人版权益](https://help.aliyun.com/zh/qwenwork/personal-benefits) | 标准版月付 98、连续包月 78 元，2,000 积分/月；高级版月付 198、连续包月 158 元，4,000 积分/月；限时注册／登录赠分 |
| [千问办公简介](https://help.aliyun.com/zh/qwenwork/qwenwork-intro) | 完整办公工具定位与会议资料整理场景，费用不能全归入录音 |
| [千问办公网页端功能](https://help.aliyun.com/zh/qwenwork/core-features-of-the-web/) | 云端任务、文档交付、钉钉 AI 听记等协同；不同版本与授权范围存在差异 |

飞书与千问部分网页为动态页面，普通网页打开器未提取出完整正文；飞书价格与权益文字、千问录音纪要入口使用 byted 搜索返回的官方网页文本核对。千问办公个人权益及网页端说明由官方网页正文再次核对。未用搜索结果中的第三方断言补齐未知价格。

此次交付核验：正文 7 张图片路径有效且不重复；作者图最后出现一次、与 Skill 原素材字节一致；正文标题、当前封面布局 JSON 和图片清单一致；图片 SHA-256 核对通过；开源与 App Store 入口保留；原附件客户名、个人口述和文件名未出现在正文。`make docs-check` 返回 `docs-check: ok`，限定文档范围 `git diff --check` 通过。新图文包 `/private/tmp/woice-wechat-2026-10-02-domestic-comparison.zip` 共 16 个文件，包含当前排字脚本与布局，ZIP 完整性和全部正文图片引用核验通过。

## 第二版：按已确认切口重写

- 用户确认标题与选题“一段录音的成本，不只是转写费”，当前 `article.md` 已完成费用、操作负担与内容去向主线的成稿；原稿保存为 `article-v1-product-intro.md`。
- 使用 `wtt-authentic-storytelling`，读取内容标准、表达 DNA、本人改写及相关参考；没有把 Skill 历史素材当作作者本次经历。
- 正文直接说明作者是 Woice 开发者，三图分别承接采集、回查与本机处理。GitHub 与 App Store 安装入口集中在文末，来源引用仍在相关事实旁保留。
- 重写时再次读取 Otter 与 MacWhisper 官方页面，并通过 Apple Lookup 回读中国区 `Woice / 0.1.8 / price=0 / 免费 / minimumOsVersion=14.0`；沿用已核对的版本差异、Apple 功能和隐私来源。
- 需求沟通为显式假设场景，不杜撰作者经历或受众反馈；未承诺本机一定更省钱、更方便或识别更准。
- v2 交付 ZIP 只包含当前正文、核对说明和三图，共五个文件；旧稿与选题方案留在项目内供追溯。

## 事实与表达边界

- 仓库依据：`README.md`、`doc/INDEX.md`、`doc/spec/2026-08-22-voice-context-source-positioning.md`、`PRIVACY.md` 和最近发行 Log。README 与 INDEX 中的历史版本/审核状态不直接作为线上现状。
- Apple 公开 Lookup 实时结果：中国区与美国区均 `resultCount=1`、`trackName=Woice`、`version=0.1.8`、`price=0`、`minimumOsVersion=14.0`。中国区 `formattedPrice=免费`、`currency=CNY`，返回页面为 `https://apps.apple.com/cn/app/woice/id6805397359?mt=12&uo=4`。
- 价格只写“当前免费”，不承诺永久免费。Apple Lookup 的下载价格不单独证明所有未来功能免费；本机无需购买云端分钟额度另由现有产品路线与实现支持。
- GitHub API 返回 `HTTP Error 403: rate limit exceeded`。改读匿名公开网页返回 HTTP 200，页面标为 Public；公开 Raw LICENSE 返回 HTTP 200，含 MIT License。开源链接已核验，未使用私有账号信息。
- 设备描述采用“本机模型主要面向 Apple 芯片 Mac”；不因 Store 构建为双架构而承诺 Intel 上各模型的表现。
- 不承诺识别率优于竞品、自动说话人识别、自动纪要、回声消除、任意 Agent 全面兼容或完整团队协作。
- 录音、导入、搜索、复听和导出为主；没有把规划中的 Agent 适配当作当前已验证卖点。
- 模型下载会联网，可选外部转写经确认后会外发；不用“永不联网”“任何内容永不离开设备”“绝对安全”等表述。
- 第一版涉及个人动机的段落为拟写作者口吻，每周 10 小时为显式假设；第二版移除这项数字假设，只使用已确认的判断和显式需求沟通示例。

## 市场来源

本次实际调用 byted-web-search 并阅读返回结果，再用官方网页核对。首次沙箱调用失败：`Failed to resolve 'open.feedcoopapi.com'`；允许联网后的同一脚本成功。搜索里的第三方对比仅用于发现线索，正文价格和能力使用以下官方依据。

| 来源 | 本稿使用的事实 |
|---|---|
| [Woice 中国区 App Store](https://apps.apple.com/cn/app/woice/id6805397359) | 当前下载价格、线上版本、macOS 最低版本与录音/模型/导出说明；Apple Lookup 实时核对 |
| [Apple Lookup 中国区](https://itunes.apple.com/lookup?id=6805397359&country=cn) | `0.1.8`、`price=0`、`minimumOsVersion=14.0` |
| [Woice GitHub](https://github.com/WaterDJiang/woice) | 公开仓库与源码构建入口 |
| [Woice LICENSE](https://github.com/WaterDJiang/woice/blob/main/LICENSE) | 源码 MIT；第三方内容许可另算 |
| [Woice PRIVACY](https://github.com/WaterDJiang/woice/blob/main/PRIVACY.md) | 默认本机、不隐式云端回退、下载与主动外发的区别 |
| [Otter Pricing](https://otter.ai/pricing) | Basic 300 分钟/月；Pro 常规月付 $16.99/人/月，年付折算 $8.33/人/月，1,200 分钟/月；页面还含限定印度发卡的促销价，未将促销价当作一般价格 |
| [Otter Privacy Policy](https://otter.ai/privacy-policy) | 服务会接收与处理用户提供的录音/会议信息；没有据此断言“会泄露” |
| [MacWhisper 官网](https://www.macwhisper.com/) | 免费版；官网 Pro €64/授权、一次性付费；本机转写、批量/字幕/会议能力 |
| [MacWhisper 版本差异](https://docs.macwhisper.com/article/40-macwhisper-whisper-transcription-difference) | 直接下载一次性授权与 App Store 周/月/年订阅的区别，可选 Assistant 服务另算 |
| [Aiko 官网](https://sindresorhus.com/aiko) | Whisper 在设备上运行；不沿用历史“所有当前版本都免费”的说法 |
| [Apple 语音备忘录转写](https://support.apple.com/zh-cn/guide/voice-memos/vm4a03609f0d/mac) | macOS 15+、Apple 芯片、地区可用性；可转写和搜索原文，避免过时地称其只能录音 |
| [Apple 语音备忘录录音](https://support.apple.com/zh-cn/guide/voice-memos/vmaa4b813415/mac) | 麦克风录音与同 Apple 账户设备间访问 |

## 图片处理与复核

只把处理后的图片放入本交付目录，不复制未脱敏原图。图片由内置 imagegen 编辑，属于原截图的 AI 脱敏版本，未用生成图冒充未经修改的运行截图，未用于 App Store 截图提交。

- `01-material-library-redacted.png`：不透明灰条遮盖客户机构、会议标题、文件名、个人口述、录音日期/时间与顶栏版本；保留列表结构、时长、音源图标和右侧操作入口。AI 处理另遮盖了若干状态文字，正文不据此推断额外功能。
- `02-menubar-redacted.png`：去除 Popover 外全部桌面/浏览器背景；保留录音来源和操作内容。原附件尺寸很小，生成版本经过放大，不作为像素级截图证据。
- `03-local-model-redacted.png`：遮盖顶栏版本和两处模型 revision。revision 是公开技术标识，本身不视为个人隐私；遮盖用于减少发布画面的技术噪声。
- 已逐张目视检查：未见原客户名称、会议标题、个人口述或周围桌面内容。使用不透明遮盖，不使用可辨认的轻度模糊。
- 文章使用相对图片路径；交付前检查三条路径、像素尺寸与文本中的敏感内容残留。
- 实际验证：三条图片路径有效且非空；正文敏感文本扫描通过；`make docs-check` 返回 `docs-check: ok`；限定本次文档范围的 `git diff --check` 通过。图 1/3 为 `1512×1040`，图 2 为 `1385×1136`；交付 ZIP 五个文件，`testzip()` 无错误。

## 最终编辑提示词

以上三张脱敏截图的首轮验收与五文件 ZIP 为 2026-10-01 的历史记录。2026-10-02 增补封面与概念插图，当前正文共七张图片，完整提示词见 `image-prompts.md`。

- 封面与两张正文线条图均为原创概念插图，不作为真实产品界面或功能测评证据。
- 用户选定封面 A“小价签，大线团”；两张正文图引用该图的小人作为角色参考，不送入真实客户内容或未脱敏截图。
- 封面使用真实喜脉喜欢体 TTF 排字，标题不删改。另附母版与同图方裁；实际公众号编辑器裁剪仍待验证。
- 作者介绍图直接复用 Skill 自带素材，不重新生成，全文最后仅引用一次。

以下三张截图的执行方式：内置 `image_gen.imagegen`；每张只引用相应原图，`transparent_background=false`。

### 图 1

> Use case: precise-object-edit. Edit this exact macOS Woice screenshot for privacy redaction for a public article. Preserve screenshot appearance, aspect ratio, all UI outside the redacted areas exactly. Only modify the material list area in left sidebar below search and status controls and above bottom settings bar. Cover ALL recording titles, filename titles, transcript excerpts, and dates and times with solid opaque neutral gray rectangular redaction bars, including the partially clipped bottom row. This covers client institution names, meeting topics, the personal self-introduction and filename. Keep microphone/video icons, material-ready status icons and text, durations if practical, scrollbar and the right empty-state panel unchanged. Also cover the top subtitle version/build line with a small solid gray bar. Do NOT invent example recordings or new UI, no readable private text left in list. No added branding or decorative elements.

### 图 2

> Use case: precise-object-edit. Privacy-redact this exact Woice menubar popover screenshot. Preserve popover shape, top triangle, Chinese UI text and controls exactly. Replace all surrounding desktop/browser background OUTSIDE the rounded popover with flat opaque white; no usernames, page text, avatars or partial browser content may remain outside. Keep menu unchanged: 录音来源, 麦克风 + 电脑声音, 麦克风, 电脑声音, 开始录音, 进入工作台, 设置, 退出 Woice. Keep original popover colors, layout and scale. No extra UI, title or labels.

### 图 3

> Use case: precise-object-edit. Privacy-redact this exact Woice model settings screenshot, preserve aspect ratio, layout, every Chinese UI label and all controls exactly. ONLY cover the top subtitle version/build line and the two long hexadecimal model revision identifiers with solid opaque light-gray rectangular bars. First revision appears on the version line directly under Qwen3-ASR 0.6B (本机) in the 本机语音转文字 card; second revision is directly below Qwen3-ASR 0.6B (本机) in the 实际转写路线 card. Preserve model name, 已下载, 已验证1个本机模型 if possible, explanatory local privacy sentences and all other UI. No new text or design changes.
