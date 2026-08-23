# Woice 品牌与 App Store 素材规格

> 状态：主视觉已定稿；品牌尺寸族与 App Store 资料骨架已准备
> 日期：2026-08-22

## 目标

- 为 Woice 建立一套能在 macOS App Icon、官网、宣传图和 App Store 中复用的品牌识别。
- 视觉首先表达“录音、转写、语音素材”，不把 Woice 误读成 Agent 网关或聊天入口。
- 保留用户确认的 PNG raster 母版、SVG 包装、Icon Composer 导入说明、PNG 尺寸族和发布元数据草案。

## 视觉决策

- 主方向：用户确认的 W 折叠波形丝带（W Folded Waveform Ribbon）。蓝色连续丝带、深色内折和微光保留附件中的声音流动与小尺寸系统波形感。
- 形态：黑色不透明方形画布 + 立体蓝色 W 丝带；系统圆角由 macOS/App Store 应用，不在图标画布里重复加系统遮罩。
- 主色：最终 raster 母版为视觉真相；Deep Ink `#172033`、Cobalt `#2D63D7`、Fold Ink `#0C1422` 作为周边文案和传播物料的参考色。
- 字体：优先 SF Pro Rounded / SF Pro Display；正文使用 SF Pro Text；网页或非 Apple 环境使用 Inter 作为回退。

## 范围

- `assets/brand/source/`：最终 PNG 母版、SVG 包装、文字锁定组合和 Icon Composer 导入说明。
- `assets/brand/exports/`：App Icon PNG、macOS Asset Catalog 和 iconset 源目录。
- `assets/brand/concepts/`：多轮视觉探索记录，不作为生产 Logo 源稿。
- `assets/app-store/`：商店素材清单、元数据草案、Mac 截图 brief 和提交前检查。

## 验收标准

- [x] W 主标在 16 px、32 px、128 px、256 px、512 px、1024 px 输出中保持清晰。
- [x] App Store 图标为不透明 sRGB PNG，至少提供 1024×1024；macOS Asset Catalog 提供 1x/2x 尺寸族。
- [x] 用户确认的 1254×1254 PNG 作为唯一生产 raster 母版；未用近似矢量重绘替代。
- [x] SVG 包装无外部图片路径以外的图形依赖；Lockup 仅将母版与文字组合。
- [x] 生成方向与最终源稿分离；最终生产资产明确保留定稿中的微光、内折和黑底。
- [ ] 真实 App UI 截图：待当前可分发 Build 与最终文案冻结后从真实运行路径采集。
- [ ] App Store Connect 的 Bundle ID、Team、隐私政策 URL、支持 URL、版权信息：待发布账号资料补齐。

## 影响面

- 不改 SwiftPM、App 运行逻辑或现有 UI；本轮只增加品牌与商店资料资产。
- 后续接入 App 时，把 `assets/brand/exports/AppIcon.appiconset/` 复制到 Xcode Asset Catalog；需要 Icon Composer 时导入 `assets/brand/source/icon-layers/woice-final-ribbon.png`，不重新拆分定稿视觉。
- App Store 截图必须来自真实 App，不使用本目录中的占位图替代产品界面。
