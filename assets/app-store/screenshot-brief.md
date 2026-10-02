# Woice Mac App Store 截图 Brief（下一版本）

> 当前 App Store 仍只有 1 张 Build 6 详情页截图。下一版改为“本地、私有、下载后离线”主叙事；所有上传图必须从下一版本最终签名 Build 重新采集。

## 导出规格

- Mac 截图使用 16:10；优先导出 `2560×1600 px`，也可使用 Apple 接受的 `1280×800`、`1440×900` 或 `2880×1800`。
- 每张图为不透明 PNG/JPEG；禁止 alpha/transparency。
- 下一版准备 6 张，按下表顺序上传；若某个真实状态无法稳定复现，则删掉该张，不用静态稿补位。
- 截图必须来自真实运行的 Woice Build，不把生成图、线框或静态宣传页当作产品截图。

## 建议顺序

| 页 | 主题 | 画面重点 | 叠加文案 |
|---|---|---|---|
| 01 | 本地与私有 | 首次设置或“文件与隐私”，显示用户选定的素材文件夹和 Finder 入口 | `声音留在你的 Mac` |
| 02 | 离线模型 | 三模型选择页，完整显示 Tiny、Qwen3-ASR、Large-v3 的建议和取舍 | `模型下载后，离线也能转写` |
| 03 | 本机素材详情 | 音频、原文、时间戳、模型来源和“已保存到本机”状态 | `音频和文字，默认不上传` |
| 04 | 素材搜索 | 素材列表、搜索和筛选，使用无隐私的演示数据 | `不用联网，也能随时找回` |
| 05 | 版本可追溯 | 同一素材的原始转录与重转写版本入口 | `原始内容不覆盖` |
| 06 | 会议声音 | 录音设置或详情中的麦克风、电脑声音与会议回放 | `只录声音，不保存屏幕画面` |

## 当前资产核对

- `screenshots/build9-actual/01-first-run-local-models-raw.png`：正式版 `0.1.4 (Build 9)` 首次设置，显示用户选择素材目录、麦克风授权和本地模型步骤。
- `screenshots/build9-actual/02-three-local-models-raw.png`：正式版 Build 9 三模型清单，显示 Large-v3、Tiny、Qwen3-ASR 的建议与状态。
- `screenshots/build9-actual/03-local-material-detail-raw.png`：正式版 Build 9 合成演示音频详情，显示“已保存到本机”、原文和 Qwen 模型来源。
- `screenshots/build9-actual/04-offline-search-raw.png`：正式版 Build 9 搜索结果原始 PNG；因窗口截图 alpha 异常，合成时使用同源无透明通道的 `04-offline-search-flattened.jpg`。
- `screenshots/build9-actual/05-transcript-versions-raw.png`：正式版 Build 9 两个本地转写版本和模型快照。
- `screenshots/build9-actual/06-meeting-audio-raw.png`：正式版 Build 9 录音与输入设置，显示本机保存、麦克风和电脑声音说明。
- `screenshots/build9-candidates/`：6 张 `1280×800` JPEG 候选，均无透明通道并已逐张目检；它们证明当前商店版画面和文案可成立，但下一版本 UI 若变化，必须由最终签名 Build 重新采集后替换。
- `screenshots/build6/01-material-detail-1280x800.png`：1280×800、PNG、无透明通道，可作为临时上传候选。
- `screenshots/build6/01-material-detail.png`：1229×768，不符合当前 16:10 首选规格，不作为上传候选。
- `screenshots/build6/01-material-detail-raw.png`：1117×768 原始 JPEG，不作为上传候选。
- `screenshots/next-version-preview/03-local-material-preview-1280x800.jpg`：基于 Build 6 真实详情页制作的视觉样式预览，1280×800、无透明通道；因来源不是下一版本 Build，不上传。
- 下一版本上传前必须逐张比对最终签名 Build；任何界面或能力差异都要重新截图，避免商店画面与提交二进制不一致。

## 版式规则

- 画面主体保留真实 macOS 窗口与系统材质；如加标题，只使用纯色/轻渐变背景和系统字体，不生成或重绘产品 UI。
- 每张图只讲一个动作，避免把 Agent、模型、权限和录音挤在同一张图。
- 前三张必须先回答“是否留在本机、是否可离线、数据是否上传”；录音入口不再作为第一差异点。
- Store 版不展示 Agent、自动粘贴、辅助功能授权或其他未包含的发行能力。
- 不展示真实 API Key、真实音频内容、个人姓名、邮箱或路径。
- 截图完成后检查 100% 与 50% 缩放下的文字可读性，并记录 Build 版本。

## 采集步骤

- 解锁测试 Mac，启动下一版本最终签名 Store Build；窗口固定为 16:10，并使用无隐私演示素材。
- 依次进入“文件与隐私”、首次模型选择、素材详情、素材库搜索、版本历史和会议录音设置。
- 每个画面先截图原始 UI，再制作带短标题的商店候选；原始截图与成品放在同一 Build 子目录。
- 用 `sips` 检查尺寸和 alpha；逐张人工确认文案没有遮挡真实状态。
