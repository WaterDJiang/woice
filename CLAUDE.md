# Woice Claude Code 指南

@AGENTS.md

## Claude Code 补充

- 通用规则只维护在 `AGENTS.md`，本文件只放 Claude Code 专属行为。
- 开始任务先读 `doc/INDEX.md`，按索引只加载当前相关 Spec、Design、Plan 和最近 Log 分片。
- 当前不创建 `.claude/rules/`；只有子路径出现与根目录不同或冲突的技术规则时才拆分，并保持根规则为共同基线。
- 必须确定执行的检查进入 Makefile、测试或 CI，不只写成提示词。
