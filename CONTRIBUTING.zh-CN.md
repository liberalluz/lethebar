# 贡献指南

[English](CONTRIBUTING.md) · 简体中文

## 开始之前

- 读 `AGENTS.md`。
- 读 `docs/specs/git-conventions.md` §2–§4。
- AI 参与的改动读 `CONTRIBUTING.ai.md`。
- 一个改动 = 一个批次 = 一个 PR。

## 流程

```text
分支 -> 提交 -> PR -> 评审 -> 合并
```

- 不要直接推 `main`。
- 分支保持短生命周期。
- 填写 PR 模板，不留占位符。
- 合并前必需检查必须通过。

## 一个 PR 的范围

- 一个 PR 是一个批次：说清一个行为变了、以及怎么验证的。不是一天的工作，也不是一个提交。
- 可以并进当前 PR 的：措辞、错别字、注释、模板同步、把文档挪到该在的位置——同一主题，在描述里单列「附带改动」。
- 必须另开的：跨主题（工具 / 文档 / 行为）的改动，以及任何改动门禁、策略或验收判据的改动。
- 判断口径：标题里需要出现「以及」，就该拆。
- 上限：diff 超过约 400 行、或碰到三个以上不相关模块，说明**批次**切大了——拆批次，不是只拆 PR。

## 评审

- 作者不能自审；作者是 AI 时，由人签字。
- 评审 diff、测试和证据。
- 豁免要记录，不能只口头同意。

## 合并

- 用 `gh pr merge --squash` 合并，不要直接推 `main`。
- 只有一笔提交的 PR 不用额外传参。多笔提交时要传 `--subject` 与 `--body-file`，否则 GitHub 会取中文的 PR 标题、或把每笔提交的正文拼在一起——用 `python infra/tool/merge/pr_merge.py --show --pr <n> --why "<理由>" --batch <Bn|none>` 读整条信息，同一条命令加 `--body-only` 写出 `--body-file` 要的那个文件。把整条信息交给 `--body-file`，标题会跟着落到正文第一行；`#38` 到 `#45` 就是这个形状。
- 合并之后跑 `python infra/tool/merge/pr_merge.py --verify-only`。它读 `origin/main` 顶上那条提交，标题或 `Why:` / `Batch:` 缺了就会失败；这条提交没有别的检查覆盖。

