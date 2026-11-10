# `manifest.json` 是什么意思

[English](manifest.md) · 简体中文

一个包是 zip。引擎先打开 `manifest.json`，只凭它决定这个包能不能装。压缩包里的
其余东西——节点、动作、美术——要等这个文件被接受之后才读。

## 三个版本，三种职责

| 数字 | 住在哪 | 回答什么 | 什么时候变 |
| --- | --- | --- | --- |
| `version` | `manifest.json`、tag、descriptor | 这是*这个包*的哪个构建 | 你改了这个包 |
| `specVersion` | `manifest.json` | 它用的是哪种包*格式* | 格式变了，不是你变了 |
| `engine` | `manifest.json` | 哪些引擎构建能跑它 | 引擎主版本离开你的范围 |

三者互相独立。一个包可以一年停在 `1.4.0`，而格式从 `2.0.0` 走到 `2.1.0`；一个还能
用的旧包，`engine` 范围可以原封不动。

`version` 是三段数字，tag 与它逐字一致：`pack/<id>/v<version>`。zip 旁边的 descriptor
文件名是 `<id>-<version>.json`，里面也是同一个字符串。

## id 是永久的

`id` 匹配 `^[a-z0-9-]+$`，并且会成为存档键：`save:<id>:<slot>`。两个后果：

- 改 id 会让所有指向旧 id 的存档变成孤儿；
- 发布 `-v2` 来表示新版本，会破坏“存档可读”的唯一一条规则。

想要干净地断代，就发一个新 id 并说明；不要复用旧的。

## 字段

| 字段 | 必填 | 类型 | 含义 |
| --- | --- | --- | --- |
| `id` | 是 | string | 永久 slug，`[a-z0-9-]+`；存档键是 `save:<id>:<slot>` |
| `version` | 是 | string | 这个包自己的版本；tag 带同一个字符串 |
| `specVersion` | 是 | string | 这个包写的是哪种格式；今天是 `2.0.0` |
| `engine` | 是 | string | `>=x.y.z <x.y.z`：这个包能跑的引擎版本 |
| `name` | 是 | string | 玩家看到的标题，语言为 `defaultLocale` |
| `protocol` | 是 | string | `linear@1`、`turn_based@1`，或引擎实现的协议 |
| `capabilities` | 是 | list | `name@version` 列表；每一个都必须在引擎里存在 |
| `mechanics` | 是 | list | 这个包要跟踪的资源名；可以为空 |
| `entry` | 是 | string | 会话开始的节点 |
| `saveSchema` | 是 | number | 整数；旧版本的存档读不了时就加一 |
| `assets` | 是 | list | `{type, path, slot}` 列表；`texture`、`audio` 或 `text` |
| `defaultLocale` | 否 | string | `data/nodes.json` 里的文字已经是哪种语言 |
| `locales` | 否 | 字符串列表 | `data/i18n/<locale>.json` 里额外带的语言 |
| `names` | 否 | object | 这个包按语言分的标题 |
| `kind` | 是（2.0.0） | string | `bundle` 或 `layer`；格式 2.0.0 起 |
| `target` | 分层时 | string | 层要改的那个包；`kind` 是 `layer` 时必填 |
| `requires` | 否 | id 列表 | 这个层玩之前需要的包 |
| `layer` | 分层时 | string | 不可玩的包补六维中的哪一维 |
| `collection` | 否 | object | 这个包属于哪个世界：`{id, names}` |
| `clock` | 否 | object | `{per: turn 或 node, every: n}`；不写就是每回合 |
| `meta` | 否 | object | 受众、时长、简介、图标：商店会显示的东西 |
| `content` | 否 | object | 视角、密度、阵容、弧光：这个包怎么讲故事 |

## 词汇

| 词 | 取值 |
| --- | --- |
| `kind` | `bundle`、`layer` |
| `layer` | `profession`、`genre`、`mod`、`content`、`meta`、`assets` |
| 资产 `type` | `texture`、`audio`、`text` |
| `clock.per` | `turn`、`node` |

## 能用的最小 manifest

这是 `templates/pack-min/manifest.json`，逐字节：

```json
{
  "id": "pack-min",
  "version": "0.1.0",
  "specVersion": "2.0.0",
  "kind": "bundle",
  "requires": [],
  "engine": ">=4.7.0 <5.0.0",
  "name": "The shortest story",
  "defaultLocale": "en",
  "protocol": "linear@1",
  "capabilities": ["text@1"],
  "mechanics": [],
  "entry": "open",
  "saveSchema": 1,
  "assets": []
}
```

`entry` 是 `data/nodes.json` 里的一个节点，`capabilities` 说明这个包用了引擎的哪些
功能，`mechanics` 为空是因为这个故事没有要跟踪的资源。

## `kind`、`layer`、`target` 三者一起出现，但不对称

`kind` 永远必填，只有两个值。接下来取决于你写了哪一个：

- **`kind: layer`** —— `layer` 和 `target` 都必填。没有维度的层会被拒绝，没有
  target 的层也会。
- **`kind: bundle`** —— 带 `target` 会被直接拒绝（`only a layer package may name
  a target`），因为 bundle 下面没有东西可坐。bundle 上的 `layer` **不**拒绝：
  它被静默忽略。

把这个不对称记在心里，尤其是当你把层改成 bundle 时：id、故事、协议才是要紧的，
但剩下的那行 `layer` 会留在文件里，看起来还像在起作用。

`layer` 说你要补 target 的六维中的哪一维；`target` 说那个包是哪个。
[一个仓，多个包](repositories.zh-CN.md) 两件事都讲，也列出引擎不强制什么。

## 引擎拒绝什么，用哪个码

| 你做了什么 | 引擎说 |
| --- | --- |
| 少一个字段，或形状不对 | 那个字段上的 `V-02` |
| id 不是 slug | `V-03` |
| `specVersion` 是这个构建不认识的格式 | `V-04` |
| `engine` 缺失、格式错，或排除了这个构建 | `V-05` |
| `kind` 或 `layer` 不是上面的取值 | `V-23` |
| `requires` 指向没装的包 | `V-24` |
| 能力不是 `name@version`，或引擎没有 | `V-27` |
| `collection.id` 不是 slug，或 `collection.names` 不是语言→标题 | `V-32` |

其中两个值得故意早失败。`V-05` 是唯一告诉玩家“引擎太旧”的码；`V-27` 是唯一告诉
作者“你要的这个构建没有”的码。两者在自己的机器上看到，都比在别人的浏览器里便宜。

## 还没生效的东西

manifest 能声明、引擎却不会照做的三件事，按可能咬人的顺序：

- 指向层的 `target` 在装配时被拒绝（`V-44`）；
- `layer: content`、`layer: mod`、`layer: assets` 生效；`genre` 与 `meta` 装了
  什么也不改；`profession` 是 bundle 自己的数据，没有东西可合并（`ADR-0016`）；
- bundle 上留下的 `layer` 被忽略，如上所述。

这些不是对格式的承诺；它们是这个构建的状态，每一条都是待修的缺陷，而不是要绕着
设计的规则。修好一条，就对所有包生效，包括旧的。
