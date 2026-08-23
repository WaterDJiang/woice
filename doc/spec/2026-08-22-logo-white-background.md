# Woice Logo 白底替换规格

## 目标

将当前生产 Logo 的黑色不透明背景替换为纯白背景，同时保持用户已确认的蓝色 W 折叠波形丝带、深色内折、微光、构图比例和尺寸不变。

## 范围

- 替换 `assets/brand/source/woice-final-ribbon-1254.png` 生产母版。
- 从母版重新生成 16/32/64/128/256/512/1024 PNG、`AppIcon.appiconset` 和 `Woice.iconset`。
- 同步 SwiftPM 运行时图标资源与 App Bundle 图标资源，重新安装并刷新 LaunchServices。
- 更新品牌说明、锁定组合和商店素材说明中的背景语义。

## 不在范围

- 不重绘 W 标记，不改色、不裁切、不改变比例或透明度。
- 不修改菜单栏的单色 `waveform` 状态图标。
- 不改动录音、转写、工作台和设置功能。
- 归档目录中的历史黑底方案只作为历史记录，不回写生产资产。

## 资产决策

| 项目 | 处理 |
|---|---|
| 生产母版 | 替换为 1254×1254、RGB、纯白底 PNG |
| 尺寸族 | 保留现有尺寸和文件名，统一从新母版确定性缩放 |
| Bundle | 保留 Asset Catalog、`Assets.car`、`AppIcon.icns` 和 PNG 资源的现有打包路径 |
| 失败回退 | 若生成结果改变 W 标记，停止替换并保留原生产母版 |

## 验收标准

- 母版、尺寸族和 App Bundle 图标四角像素为纯白，且无透明通道。
- W 标记在替换前后保持相同尺寸、位置和视觉细节；内部深色折叠仍保留。
- `make docs-check`、`make harness-check`、`make verify` 和 `make install` 通过。
- `/Applications/Woice.app` 的 `Info.plist` 含 `CFBundleIconName=AppIcon` 与 `CFBundleIconFile=AppIcon`，签名校验通过。
- Finder/Launchpad/Dock 刷新后显示白底 Logo；菜单栏录音状态图标不变。

## 顺序

1. 生成并人工检查白底候选。
2. 备份旧母版，替换生产母版及说明文档。
3. 运行品牌导出脚本并同步 SwiftPM 资源。
4. 构建、打包、验签、安装和刷新系统图标缓存。

