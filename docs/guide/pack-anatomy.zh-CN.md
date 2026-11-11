# 一个包是什么

[English](pack-anatomy.md) · 简体中文

一个包就是一个 zip。里面是数据：文字、数字，偶尔有图或声音。它不含程序。
引擎读这些数据，判断它们是什么意思，再画出来。

这就是为什么一个从没做过引擎的人也能写包。

## 用一句话说信封

压缩包的根目录下只有一个文件，`manifest.json`；其余全部在 `data/`、`assets/`
或 `i18n/` 下面。

别的东西——一个多余的 `README.md`、误压进去的 `dist/`、一个 `.DS_Store`——在
上传之前就会被拒绝，因为形状靠猜的包，装不上时也只能靠猜。

## 四条硬规则

| 规则 | 为什么 | 谁来拒绝 |
| --- | --- | --- |
| 根目录只有 `manifest.json`，下面只有 `data/`、`assets/`、`i18n/` | 引擎知道去哪找，所以从不扫描 | 上传前由 `check_pack.py` |
| 没有可执行文件、没有符号链接、没有绝对路径、没有 `..` | 包是数据，引擎不会从里面运行任何东西 | `check_pack.py` |
| id 是小写 slug，且永不改变 | 它是存档键，`save:<id>:<slot>` | 安装时 `V-03` |
| `engine` 是一个包含当前构建的版本范围 | 旧引擎读不了新格式，就应该说出来 | 安装时 `V-05` |

包 id 允许连字符（`^[a-z0-9-]+$`）；写在数据文件里面的 id 不允许：动作、资源、池、关系实体都满足 `^[a-z][a-z0-9_]*$`，否则 `V-16` 在安装时拒绝整个包。

信封要被检查两次，这是故意的：一次是你，在你准备发布的那份字节上；一次是引擎，
在玩家浏览器刚下载的那份字节上。只有第二次能保护玩家，所以即使你跳过了第一次，
它也在。

限额：500 项、单文件 4 MiB、整包 32 MiB。对纯文本很宽裕，对视频很紧；一个包需要
更多，就说明它需要拆成两个包。

## 一棵可抄的目录树

这是 `templates/pack-min/`，能装能玩的最小包：

```
templates/pack-min/
├── manifest.json
└── data/
    └── nodes.json
```

两个文件都短到可以手抄。下面是完整的 manifest：

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

发布前把 `id` 改成你自己的；其余字段可以等到有需要再动。`manifest.json` 声明入口
节点、协议和格式。`data/nodes.json` 里是三个节点：第一个给出两个选择，每个选择
都会结束故事。

```text
data/nodes.json
  nodes[0] open   — text, choices: [ {label, next: "river"}, {label, next: "ridge"} ]
  nodes[1] river  — text, choices: []
  nodes[2] ridge  — text, choices: []
```

`choices` 为空，就是故事结束。引擎不需要为此再加一个标志。

`templates/pack-turn/` 是同一个故事换一种协议：一个节点、没有选择、下面一个菜单，
再多三个数据文件——见[八块积木](bricks.zh-CN.md)。

## 一个 bundle 和一个 layer，并排看

layer 是同样形状的包，只是 manifest 写明它改什么。最小的一个，完整地，对照上面的
bundle：

```json
{
  "id": "sanguo-content",
  "version": "1.0.0",
  "specVersion": "2.0.0",
  "kind": "layer",
  "layer": "content",
  "target": "sanguo",
  "requires": [{ "id": "sanguo", "version": "1.0.0" }],
  "engine": ">=4.7.0 <5.0.0",
  "name": "Three Kingdoms, in the first person",
  "defaultLocale": "en",
  "protocol": "linear@1",
  "capabilities": ["text@1"],
  "mechanics": [],
  "entry": "open",
  "saveSchema": 1,
  "assets": [],
  "content": { "view": "first", "density": "sparse", "cast": [], "arc": [] }
}
```

按这个顺序问三个问题，就能分清两者：

1. **它能自己开一局吗？** 只有 `bundle` 能。答案是不能，这个包就是 layer。
2. **它补另一个包的哪一格？** 那就是 `layer`：`profession`、`genre`、`mod`、
   `content`、`meta` 或 `assets`。
3. **那个包是哪个？** 那就是 `target`，是一个玩家也必须装的 bundle 的 id。

layer 仍然重复 bundle 需要的字段——`protocol`、`mechanics`、`entry`、`saveSchema`、
`assets`——尽管合并时其中大部分会被忽略。这是今天的形状，不是想要的形状；指南的
[最后一页](README.zh-CN.md)列出了还粗糙的地方。

## 玩家安装时发生什么

1. 读取压缩包；`check_pack` 的规则在这些字节上再跑一遍。
2. `manifest.json` 逐字段校验，`V-02` 到 `V-42`。
3. 包写入浏览器存储，所以刷新后还在。
4. 开始一局时在 `entry` 建会话，读 `data/nodes.json`。

这一串里没有一步读网络。安装是对玩家选定文件的本地操作；这也是为什么包一装上就
能离线玩。
