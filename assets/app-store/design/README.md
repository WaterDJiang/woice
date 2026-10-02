# App Store 截图视觉包装

`woice-local-wave-background.png` 是截图候选使用的低干扰品牌背景，只包含抽象渐变和声波，不包含产品界面、文字或状态。

生成提示词：

> Create a clean, premium 16:10 background for a macOS App Store product screenshot for an app named Woice. Abstract privacy-and-local-computing atmosphere only: deep midnight navy to cobalt blue gradient, extremely subtle soft waveform ribbon and a faint local-device halo, quiet native macOS utility aesthetic, generous negative space, no objects, no people, no screens, no app UI, no logos, no icons, no letters, no words, no typography, no numbers. The background must remain unobtrusive so a real app screenshot and Chinese headline can be placed over it. Flat polished marketing background, high contrast near the top for white text, subtle depth, no noise, no visible watermark.

使用边界：

- 背景可复用；每张产品界面必须从待提交的最终签名 Build 实机采集。
- 中文标题由 `render-screenshot-card.swift` 使用 macOS 系统字体绘制，不交给生成模型。
- 不允许修改、补画或生成产品 UI；如真实状态与标题不一致，废弃该张候选。

