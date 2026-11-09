<!-- translation-of: README.md -->
# Lethebar

[English](README.md) · 简体中文

> 一个不内置任何玩法的引擎，配上一组既带场景、又带玩法的插件包。
> 换故事不用重做引擎，换玩法不用重做故事。

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE) [![Engine](https://img.shields.io/badge/engine-Godot%204-478cbf.svg)](https://godotengine.org)

## 状态

**v0.7.2 已发布，一局可以由不止一个包拼起来。** 三国与修仙分别从各自的仓库发布成可安装的包
——`pack/sanguo/v1.0.0`、`pack/sanguo-content/v1.0.0`、`pack/sanguo-hard/v1.0.1` 与
`pack/cultivation/v1.0.0`——本仓只留一个冒烟包（`duel`），好让引擎自己的测试有东西可打开。
世界包是 `bundle`：它自带故事与规则。层包用 `target` 点名它改哪个 `bundle`，然后改动它
——`content` 层改这个故事的讲法，`mod` 层改玩法。包页会列出点名本包的层；层默认不勾，因为
它会改玩家没要求改的规则；存档会记下这一局用了哪一套，重载时按同一套重放。v0.7.2 补上那次修复之后的事：一个包是层，是因为它写着
`kind: layer`，不是因为它带了 `target`；包页可以把一个包或它的某一层移除。

每个世界仓自己构建包、在发布前检查压缩包的信封，然后在 Release 上放两个文件：`<id>.zip`
与 `<id>-<version>.json`，后者写明那些字节的哈希。引擎在安装时再查一遍，所以一个被截断或
被手改过的包，在能玩之前就会被拒。

玩家从文件装包：去世界仓的 Release 下载 zip，再在界面里挑它。不提供「填链接直接装」，
因为 GitHub 的 Release 资产不带 CORS 头，浏览器会拒绝这次抓取。

升级注意：玩过旧内建包的浏览器里，那些包还是 `0.1.0`，而 `V-03` 拒绝同一个 id 的第二次
安装。在包页把旧包移除（连按两次「移除」），再装世界包即可，不必再清站点数据。

已知限制：图片与声音只画进一条图带和一列立绘，且只认 PNG、JPEG 与 WAV；一局的时钟
按回合或节点计，从不按墙上时间；随包字体覆盖 BMP 与 CJK 扩展 A，扩展 B 仍会画成方框；
势力名与弧光段名是包里的文本，还不会跟随读者语言；受众只被校验，暂时没有任何筛选；
两个层改同一条目的不同字段，目前还不算冲突。

下一步：作者入口已经随这一版发出——`docs/guide/` 讲清一个包、它的 manifest、八块积木、两个协议和每个拒绝码，`templates/` 里有两个一屏能读完的包，`github.com/liberalluz/lethebar-pack-template` 是带好门禁的起手仓。这些都不在 `v0.6.0` 里。

再往后：第一次真正的装配——一次运行由两个仓的包拼成，上面压一个 mod 与一个内容层。iOS 构建没有排期；等真机验收的成本高过它省下的，再回来做。

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

三条命令都只做检查。要玩，打开导出的构建，或直接开
`https://liberalluz.github.io/lethebar/`。

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
