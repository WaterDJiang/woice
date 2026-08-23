# Woice 品牌资产

主视觉已定为用户确认的“W 折叠波形丝带”PNG：保留蓝色立体丝带、深色内折和微光，并以白色不透明底适配 App Icon 与传播场景。

## 资产入口

- `source/woice-final-ribbon-1254.png`：用户确认的精确 raster 母版，当前唯一生产真相。
- `source/woice-mark.svg`：引用上述母版的 SVG 包装，便于支持 SVG 的宣传工具读取；不是重新绘制的假矢量稿。
- `source/woice-lockup.svg`：母版 + `Woice` 文字组合，适合官网和宣传图。
- `source/icon-layers/woice-final-ribbon.png`：Icon Composer 使用的整合前景/背景源；定稿视觉不拆成伪分层。
- `source/icon-composer-layer-spec.md`：Icon Composer 导入边界和旧版归档说明。
- `exports/AppIcon.appiconset/`：macOS Asset Catalog 尺寸族。
- `exports/Woice.iconset/`：macOS 本地安装包可继续转换为 `.icns` 的完整源目录；当前以 Asset Catalog 为发布真相。
- `exports/woice-app-icon-{16,32,64,128,256,512,1024}.png`：由精确母版确定性缩放的通用尺寸族。
- `concepts/`：本轮视觉探索方向，只用于记录设计判断，不作为生产 Logo 源稿。

## 颜色

| 名称 | HEX | 用途 |
|---|---|---|
| Deep Ink | `#172033` | 正文深色、主背景和锁定组合文字 |
| Warm Paper | `#F7F2E9` | 前景弧线、浅色背景 |
| Fold Ink | `#0C1422` | W 丝带内折线、深色轮廓 |
| Record Coral | `#D97B68` | 录音状态、少量动作强调 |
| Cobalt | `#2D63D7` | 链接、选择态、传播物料的辅助色 |
| Quiet Mist | `#E8EDF7` | 浅色容器与分隔背景 |

## 使用规则

- 主标四周至少保留主标高度的 `0.5×` 空间；App Icon 由系统负责圆角遮罩。
- 小于 16 px 不添加文字；优先使用已导出的 16 px 图标或原生系统图标适配。
- 当前定稿中的微光、深色内折和白底是设计的一部分；不得裁切、去光、改色或替换为旧版扁平 W。
- 不在主标旁添加“AI”字样。
- 不用麦克风、耳机或通用 AI 星光替代主标；它们会把产品带向会议硬件或 Agent 网关。
- 宣传文案优先写“录音、转写、语音素材”；“发送给 Agent”只作为素材完成后的次级动作。

## 推荐字体

- Apple 平台：`SF Pro Rounded`（Logo 组合）、`SF Pro Display`（标题）、`SF Pro Text`（正文）。
- 非 Apple 回退：`Inter`。

## 重新导出

```bash
zsh assets/brand/tools/render-brand-assets.sh
```

导出脚本从 `source/woice-final-ribbon-1254.png` 通过 `sips` 确定性缩放，不重绘图形，避免破坏定稿中的微光和内折细节。若设计工具生成的候选存在近白色背景，先用 `tools/normalize-white-background.swift` 将与边缘连通的背景归一为纯白，再替换生产母版。

`.icns` 不是 App Store Connect 的必交文件；当前环境的 `iconutil` 对生成的 iconset 返回 `Invalid Iconset`，因此不把未经验证的 `.icns` 写入交付物。需要本地安装包时，在 Xcode/图标工具链可用的环境中从 `Woice.iconset/` 重新转换。
