# Lethebar

[English](README.md) · 简体中文

> 一个不内置任何玩法的引擎，配上一组既带场景、又带玩法的插件包。
> 换故事不用重做引擎，换玩法不用重做故事。

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE) [![Engine](https://img.shields.io/badge/engine-Godot%204-478cbf.svg)](https://godotengine.org)

## 状态

**v0.0.0 开发中，现在还不可玩。**

- 首个可玩版本的目标日期：**2026-12-31**
- 首个可玩版本的验收标准：在浏览器里打开，选一个内置包，玩完一段场景
- 当前进度：批次 `B1`（插件包加载与校验）尚未开始

本仓库现在公开，是因为插件规范要先被看见、被挑战。

## 它能做什么

- **四层结构，依赖方向只有一个**：引擎（规则运行时 + 渲染运行时）、插件层（职业包、品类包、机制 mod）、资产层、Meta 配置。引擎从不认识具体玩法。
- **插件包是数据，不是代码**：一个包是带 `manifest.json` 的普通 zip，引擎只解释它声明的协议，拒绝执行包内代码。
- **一个引擎，几种玩法**：协议注册表内置 `linear@1` 与 `turn_based@1`，换包不改引擎。
- **每局可复现**：相同的选择得到相同的结果；种子由包 id 与起始计数导出，不读系统时钟。
- **离线可玩、存档可用**：加载过一次之后，刷新仍能开新局、读旧档；每个包三个存档位。

## 快速开始

```bash
git clone https://github.com/liberalluz/lethebar.git
cd lethebar
python infra/stage_builtin.py                  # 把内置包暂存进 app/
godot --path app --headless --quit              # 导入资源；生成 app/.godot/（已忽略）
godot --path app --headless -s res://tests/run_tests.gd   # 规则层断言
```

三条命令都只做检查，**跑起来看不到游戏**——v0.0.0 之前本仓库没有可玩内容。

## 命令

| 命令 | 作用 |
|---|---|
| `python infra/checks/check_changelog.py` | 分支上有 `feat` 或 `fix` 提交却没有新的 `changelog.d/` 分片时报错 |
| `python infra/checks/check_tree.py` | 检查仓库布局：根目录条目是否在白名单内、有无生成物被跟踪 |
| `python infra/stage_builtin.py` | 把 `content/builtin/*` 打成 zip 暂存到 `app/builtin/`，测试与导出前先跑 |
| `python infra/export_web.py` | 导出 web 构建到 `build/web/`，需要 `GODOT_BIN` 与 `GODOT_TEMPLATE_APPDATA` |
| `python infra/verify_web.py` | 用无头 Chrome 加载该构建并输出控制台结果，需要 `node` |
| `godot --path app --headless --quit` | 资源导入与 `app/.godot/` 重建 |
| `godot --path app --headless -s res://tests/run_tests.gd` | 规则层断言（协议、装配、存档编码） |
| `python infra/tool/batch/batch.py` | 按批卡生成分支与检查清单 |

目前**没有 CI**。上面这张表就是当前的门禁，本地跑通才算过；等 CI 建起来后，这张表必须与工作流同一个 PR 一起改。

## 项目结构

| 目录 | 职责 |
|---|---|
| `app/` | Godot 工程根（`project.godot`）与引擎代码：`core/`（规则运行时）、`protocols/`（协议注册表）、`render/`（渲染运行时）、`ui/`、`tests/`（无头断言） |
| `content/` | 内置插件包与其数据，一个包一个目录 |
| `infra/` | 构建、导出、部署脚本，含 `stage_builtin.py` |
| `infra/tool/` | 随仓库携带的 Nebula 工具：批次执行、仓库策略、发布 |
| `docs/` | 规格、决策、intent（[docs/README.md](docs/README.md)） |

## 架构

引擎分两层：**规则运行时**决定一局如何推进，**渲染运行时**决定画面如何呈现。插件层位于其上，通过声明使用哪一层能力（`dimension`、`requires`）接入，而不是自带渲染器。依赖方向只有一个：`render → session → protocol → data`。

细节见 [SDD](docs/specs/controlled/SDD.md)，为什么这么定见 [ADR-0001](docs/decisions/0001-engine-and-language.md)。

## 插件格式

插件包是普通 zip，根目录一个 `manifest.json`，含 `id`、`version`、`specVersion`、`engine`、`protocol`、`capabilities`、`mechanics`、`entry`、`saveSchema`、`assets`。

引擎加载时按 `V-01`…`V-09` 逐项校验：缺资源只警告、不崩溃；非法包被拒绝且游戏仍可用。见 [SDD §3](docs/specs/controlled/SDD.md)、[ADR-0002](docs/decisions/0002-plugin-package-zip.md)、[ADR-0003](docs/decisions/0003-plugins-carry-data.md)。

## 文档

| 想找什么 | 去哪 |
|---|---|
| 为什么做这个 | [docs/intent/](docs/intent/) |
| 应当如何 | [docs/specs/](docs/specs/) |
| 定了什么、否掉了什么 | [docs/decisions/](docs/decisions/) |

`docs/` 的放置判据：应当如何 → `specs/`；定没定 → `decisions/`；为什么 → `intent/`；怎么操作 → `runbooks/`。

## 参与贡献

- 提交前读 [CONTRIBUTING.md](CONTRIBUTING.md)
- 用 AI 改代码的，另读 [CONTRIBUTING.ai.md](CONTRIBUTING.ai.md)：AI 改动需人审查并附测试或证据，作者不能自审
- 想提插件规范意见，在 issue 里贴一份 `manifest.json` 草稿，比讨论抽象概念有用

## 安全

漏洞报告方式见 [SECURITY.md](SECURITY.md)。插件包会被当作不受信任的输入处理。

## 许可

引擎以 [Apache License 2.0](LICENSE) 授权：可商用、可再分发，需保留版权声明与 [NOTICE](NOTICE)。

第三方依赖与资产的署名统一登记在 [NOTICE](NOTICE)；插件包由各自作者授权，不在本仓库的许可范围内。
