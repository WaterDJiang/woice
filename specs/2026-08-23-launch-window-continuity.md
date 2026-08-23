# Finder 启动与工作台窗口连续性规格

## 目标

- 双击 Woice.app 后，用户能在 Dock/应用切换器中确认 Woice 已启动，并看到工作台窗口。
- 保留菜单栏快速录音入口、状态图标和退出操作。
- 单实例锁继续生效，不因为显示 Dock 图标而创建第二个录音控制器或第二个 Connector。

## 边界

- 只调整 App 的 macOS 激活身份，不改变录音、权限、素材和 Agent 语义。
- 使用 regular App + AppKit `NSStatusItem` 保留菜单栏控制器；不使用会把应用激活策略压成 prohibited 的 `MenuBarExtra`；Dock 图标使用现有白底 Woice Logo。
- 稳定签名和 TCC 继承仍由 WPC-07/08 的真实 Mac 验收负责。

## 验收

- Finder 双击或 open -a /Applications/Woice.app 后，Woice 进程存活且工作台可见。
- 无论上次停留在素材库、录音详情、处理任务或设置，外层窗口标题保持“Woice 工作台”；具体页面标题只作为内容层级，不替换统一工作台身份。
- 菜单栏仍有 Woice 状态图标，菜单栏录音与工作台录音状态一致。
- 重复启动不会创建第二个进程或第二个菜单栏入口。

## 验收脚本边界

- 菜单栏 `NSPopover` 在 AX 树中可能保留一个隐藏的 `AXDialog`，名称通常是 `Window`；启动、无障碍和导入 Journey 必须按窗口名称匹配“Woice 工作台”，不能把 `front window` 的顺序当作工作台身份。
- 关闭工作台后，单实例进程可以继续保留菜单栏 Popover；重开验收只统计名称为“Woice 工作台”的窗口，不能把隐藏 Popover 误报为第二个工作台。
