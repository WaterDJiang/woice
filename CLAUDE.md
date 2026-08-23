# Woice Claude Code 指南

@AGENTS.md

## Claude Code 补充

- 开始任务先读 `doc/INDEX.md`，按索引只加载当前 spec、plan 和最近 log 分片。
- 通用项目规则只维护在 `AGENTS.md`；不要在本文件复制一份。
- 团队达到 5 人或出现模块专属冲突规则时，再创建 `.claude/rules/`；当前不预设路径规则。
- 确定性强制项进入 Makefile、测试或 CI，不只写成提示词。

