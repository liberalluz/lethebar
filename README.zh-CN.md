<!-- translation-of: README.md -->

# Lethebar

[English](README.md) · 简体中文

> 一个不内置玩法的引擎，故事与玩法规则都由包提供。
> 换故事不用重编引擎，换规则不用重写故事。

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE) [![Engine](https://img.shields.io/badge/engine-Godot%204-478cbf.svg)](https://godotengine.org)

## 状态

**v0.9.0 已发布：引擎能在手机上跑。iOS 由 Codemagic 构建，输入、选包、从「文件」打开包都走系统。**

引擎仍只带一个 smoke 包 `duel`，好让它自己的测试有东西可开。其他包由各自仓库发布，[市场](https://liberalluz.github.io/lethebar-marketplace/)列出已发布的包。

## 这是什么

- **引擎，不是游戏。** 它负责规则运行时、渲染运行时和存档格式；故事、规则、图片都来自包。
- **包是数据。** 一个包是带 `manifest.json` 的 zip；引擎读它、检查它，拒绝执行里面带的代码。
- **一局 = 一个 bundle + 零或多个层。** bundle 给故事和规则；层只改其中一块——`content` 决定故事怎么读，`mod` 改数值与动作，`assets` 换图和声音。
- **同一份存档重放出同一局。** 种子来自包 id 和起始计数，不读墙钟；同一次掷骰在一回合内不会重掷。它跑在浏览器里，首次加载后可以离线继续。

## 架构

三段运行时共用一层数据：**规则运行时**（`app/core/session.gd`、`protocols/`、`bricks/`）决定一局怎么推进，**渲染运行时**（`app/render/`、`app/ui/`）决定它怎么被画出来，**数据层**（`manifest_schema`、`package_validator`、`package_loader`）决定一个包能说什么。

依赖单向：`render → session → protocols/bricks`，上层只读数据层，不反向。扩展点只有四个——协议、积木、能力、层——包格式是它们之间唯一的契约。

细节见[架构页](docs/specs/architecture.md)与 [ADR-0001](docs/decisions/0001-engine-and-language.md)（英文受控文档）。

## 游玩

打开[线上构建](https://liberalluz.github.io/lethebar/)或自己导出的构建，在包页安装包：从包的 Release 下载 zip，选文件，开局。不支持直接填 Release 链接，因为 GitHub 的 release asset 不带 CORS 头，浏览器会拒绝请求。每个包三个存档槽；加载过一次之后可以离线玩。

## 快速开始

```bash
git clone https://github.com/liberalluz/lethebar.git
cd lethebar
python infra/stage_builtin.py                              # 把内置包 stage 进 app/
godot --path app --headless --quit                          # 导入资源；生成 app/.godot/（已 git-ignore）
godot --path app --headless -s res://tests/run_tests.gd     # 规则层断言
```

要构建浏览器包，运行 `python infra/export_web.py`（需要 `GODOT_BIN` 和 `GODOT_TEMPLATE_APPDATA`）。

想写包？从[作者指南](docs/guide/README.zh-CN.md)开始。[`templates/`](templates/) 里的两个包小到一屏能读完，[`lethebar-pack-template`](https://github.com/liberalluz/lethebar-pack-template) 是一个门禁已经接好的起步仓库。

## 项目结构

| 目录 | 负责什么 |
|---|---|
| `app/` | Godot 工程与引擎：`core/`（规则运行时）、`protocols/`、`render/`、`ui/`、`tests/` |
| `content/` | 内置 smoke 包，一个包一个目录 |
| `infra/` | 批次执行器、检查器、发布与导出工具、web 技术栈 |
| `docs/` | 意图、规格、决策、作者指南与运维手册 |

## 文档

| 想找什么 | 在哪 |
|---|---|
| 为什么做这个 | [docs/intent/](docs/intent/) |
| 应该是什么样 | [docs/specs/](docs/specs/) |
| 决定过什么、否决过什么 | [docs/decisions/](docs/decisions/) |
| 怎么写一个包 | [docs/guide/README.zh-CN.md](docs/guide/README.zh-CN.md) |
| 怎么发一个版本 | [docs/runbooks/release.md](docs/runbooks/release.md) |

## 参与贡献

- 开 PR 前先读 [CONTRIBUTING.md](CONTRIBUTING.md)。
- 用 AI 改代码？还要读 [CONTRIBUTING.ai.md](CONTRIBUTING.ai.md)：AI 的改动要有真人评审，加上测试或证据；作者不能自批。

## 安全

见 [SECURITY.md](SECURITY.md)。包是不可信输入：引擎在安装前校验一次，开局前再校验一次。

## 许可

引擎采用 [Apache License 2.0](LICENSE)：允许商用与再分发，保留版权声明与 [NOTICE](NOTICE) 即可。

第三方依赖与素材的署名在 [NOTICE](NOTICE)。包由各自作者授权，不适用本仓库的许可。

