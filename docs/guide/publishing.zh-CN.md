# 发布一个包

[English](publishing.md) · 简体中文

包以文件的形式到达玩家，文件以 GitHub release 资产的形式到达玩家。这一页讲从
一个目录走到一次发布的六条命令，以及漏掉其中一条时失败的两件事。

## 六条命令

在放你的包的那个仓里运行。`pack.py`、`check_pack.py` 和 `fixtures.py` 是从引擎复制过来的三个
文件；引擎的其他东西都不需要。

```text
python infra/tool/release/pack.py self-test      # 工具在这台机器上能用
python infra/tool/release/pack.py build packs/<id> --out dist
python infra/checks/check_pack.py dist/<id>.zip  # 信封与 manifest
python infra/tool/release/pack.py hash dist/<id>.zip   # 写 dist/<id>-<version>.json
python infra/tool/release/preflight.py --pack packs/<id> --repo <owner>/<repo> --tag pack/<id>/v<version>
python infra/tool/release/pack.py publish dist/<id>.zip --repo <owner>/<repo> --tag pack/<id>/v<version> --apply
```

`self-test` 建自己的夹具，所以它失败，是你的 Python 和 zip 工具的问题，不是你的包
的问题。`hash` 写 zip 旁边的 descriptor；永远不要手改。

## 从一个已经能用的仓库开始

`github.com/liberalluz/lethebar-pack-template` 里有两个工具、三步工作流和一个能跑
的示例包；点 **Use this template**，替换示例，跳过上面的手工拼装。它按引擎
`v0.9.0` 测过，它自己的门禁在对外提供之前跑绿。

## 一个 tag、一次发布、两个资产

| 东西 | 取值 | 例子 |
| --- | --- | --- |
| tag | `pack/<id>/v<version>` | `pack/pack-min/v0.1.0` |
| 资产一 | `<id>.zip` | `pack-min.zip` |
| 资产二 | `<id>-<version>.json` | `pack-min-0.1.0.json` |

tag 里的版本、`manifest.json` 里的版本、descriptor 文件名里的版本，是同一个字符串。
三者不一致时，没有任何东西会大声失败——这正是把契约写在这里的原因。

同一个包的第二次发布是新 tag：`v0.1.1`。tag 永不移动。

重跑 `publish` 会先读 release：已经存在且哈希相同的资产不动；缺的补上；不同的拒绝，只有 `--force` 能替换（命令会打印两个哈希）。这样，已发布的产物还是玩家验证过的那一份。

## README 里的表

一个仓的 README 带三样读者安装前会看的东西：有几个包、它们共享哪个 spec 和
engine、每个包一行。从 manifest 生成，不要手写：

```text
python infra/tool/release/pack.py badge . --write README.md
python infra/tool/release/pack.py badge . --check README.md
```

`--write` 只替换 `<!-- pack-badges:begin -->` 与 `<!-- pack-badges:end -->` 之间的
块；`--check` 在某行对不上时点名包与字段，并 exit 1。`packs` 徽章数所有包，包括
层，因为层也是单独安装、单独发布的；`Kind` 列说明哪几行可玩。`spec` 与 `engine`
只在所有包一致时打印；否则徽章写 `mixed`，行里带准确值。`engine` 是唯一要紧的
那个：运行中的引擎不满足的范围，安装时会被拒绝（`V-05`）。

表变长时，用 `--fold` 把它收到一次点击的摘要后面；折叠的表把计数留在摘要里，
`--check` 也会比对那个计数。`--write` 从不自己改变形态：折叠的表跨版本仍然折叠，
想展开就显式用 `--flat`。

## 发布正文

`publish.py` 从文档仓的 `product/release-notes/<version>.en.md` 取正文；`--body-file`
可以覆盖。它**从不**回退到 `CHANGELOG.md`：发布说明对玩家讲变了什么，changelog
讲一个批次做了什么。缺发布说明是错误，不是把批次清单发到玩家标题下的理由。

`publish.py` 只写引擎的发布：正文路径和证据目录都只按引擎版本命名，所以它拒绝
一个不是该版本的 tag。包的发布属于包自己的仓库——那边的正文在
`product/release-notes/<id>/<version>.en.md`，证据在
`records/<YYYY-MM>-release-<id>-<version>/`。

## 作者门禁

把引擎里的 `infra/ci/author-gate.yml` 复制到 `.github/workflows/gate.yml`，改一行：
`ENGINE_REF`，它钉住你的检查跑在哪个引擎版本上。工作流只做三件事：

1. `build` —— 包目录变成 zip；
2. `check_pack` —— zip 被拒或通过；
3. `publish` —— 只对 `refs/tags/pack/` 下的 tag，且只有前两步通过时。

让 `ENGINE_REF` 是一个 tag 而不是 `main`，意味着引擎的一次改动不会一夜之间把你
的构建变红。

## 两件让人意外的事

**release 资产不带 `Access-Control-Allow-Origin`。** GitHub 会提供它，但另一个源
的页面取不到。所以玩家装包，是下载 zip 再选 "Install a pack (.zip)…"，不是粘
链接。链接入口是给能抓取的壳用的；在浏览器里它每次都会失败。

**引擎自带的测试故事不是你的故事。** 引擎不再内置世界之后，全新安装只显示一个
没有多少可读玩法的冒烟包。你的包替换它。

## 发布之前

| 检查 | "没过"通常意味着 |
| --- | --- |
| `manifest.json` 能解析，且点名一个入口节点 | 多了一个逗号，或节点在指向它的选择之后改了名 |
| 三个版本一致 | `version` 只在一处加了 |
| `check_pack` 接受 zip | 压缩包根目录有杂文件，或图片超过限额 |
| descriptor 存在，且与 zip 的 sha256 一致 | 跳过了 `hash`，或 hash 之后又重建了 zip |
| release 有两个资产 | 上传在不同 tag 下跑了两遍 |
| 资产能通过网络访问 | 仓库是私有的，或 release 还是 draft |

六项全过，下载 zip 的玩家就能装上。这就是全部测试。

## 从哪个模板开始

随引擎发布两个模板，每次门禁都会检查：发布前，每个都会被构建、被 `check_pack`
读取、装进引擎并玩一遍。

| 模板 | 协议 | 它多了什么 |
| --- | --- | --- |
| `templates/pack-min/` | `linear@1` | 一个 manifest 和 `data/nodes.json`；三个节点、两个选择 |
| `templates/pack-turn/` | `turn_based@1` | 同一个节点，加上 `data/ledger.json`、`data/actions.json`、`data/phases.json` |

故事从一场戏走到下一场、只做这件事，就从 `pack-min` 开始。一场戏下面有动作菜单，
或这一局需要回合上限，就从 `pack-turn` 开始。复制一个再改数据文件，比从空目录
开始快，因为那些你本来会忘的字段已经在位了。

