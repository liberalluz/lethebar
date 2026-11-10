# 一个仓，多个包

一个世界通常会长出不止一个包：主故事、第二个可玩版本、别人写的内容层。它们并排
住在同一个仓里，各自独立发布。

```
your-world-repository/
├── packs/
│   ├── sanguo/          底包故事，kind: bundle
│   ├── sanguo-cards/    另一个可玩包，kind: bundle
│   ├── sanguo-content/  内容层，kind: layer
│   └── sanguo-hard/     mod 层，kind: layer
├── infra/               两个工具，以及你想放的其他东西
└── .github/workflows/   一条门禁，三步
```

`packs/` 以上的东西都不属于某个包。玩家下载的压缩包里是 `manifest.json` 和
`data/`、`assets/`、`i18n/`——从来不是包着它的那个仓库。

文件夹名引擎不读，但请让它等于 id：这是唯一一个错误很容易被发现的地方。

## 两种形态：一种开一局，一种改一局

每个包都声明 `kind`，只有两个值。

| `kind` | 玩家能单独开吗 | 它带什么 | 需要 `layer` 和 `target` 吗 |
| --- | --- | --- | --- |
| `bundle` | 能，自己就能 | 协议、入口节点、`data/nodes.json` | 不需要，而且带 `target` 会被拒 |
| `layer` | 不能 | 另一个包的某一维 | 两个都要 |

一局永远是**一个 bundle 加零个或多个层**。引擎从 bundle 取协议、入口节点和故事；
层只提供那个 bundle 的一部分，别的都不管。所以层自己不是游戏，也所以每一组要装
配的包，里面必须正好有一个 bundle。

`genre` 在形状上是例外：带来一整套别的玩法的包，是 `bundle`，不是层。一个世界里
两个 bundle，是并排的两款游戏，不是一个底包加一个补丁。

## 一个层能补的六个维度

`layer` 说明这个包替换 target 的哪一部分。

| `layer` | 补什么 | 例子 |
| --- | --- | --- |
| `profession` | 世界本身：势力、地盘、段位、地名 | 同一时代的另一张地图，是另一个 `bundle` |
| `genre` | 玩家怎么参与：选择、菜单、一手牌 | *(实践中是 `bundle`)* |
| `mod` | 别人已经声明过的数值与成本 | 更紧的经济、一个新动作 |
| `content` | 故事怎么讲：视角、密度、阵容、弧光 | 同一场战争，第一人称 |
| `meta` | 商店那几行：受众、时长、简介、图标 | 面向更短时长的剪辑 |
| `assets` | 图、声、文本文件 | 重画的一套牌面 |

`content` 整块替换；`mod` 逐字段合并，只有两个层写同一字段时才冲突。

## 一个包、一个 tag、一次发布、两个资产

| 包 | tag | Release 里放什么 |
|---|---|---|
| `sanguo` | `pack/sanguo/v1.1.0` | `sanguo.zip`、`sanguo-1.1.0.json` |
| `sanguo-cards` | `pack/sanguo-cards/v1.0.0` | `sanguo-cards.zip`、`sanguo-cards-1.0.0.json` |

一个仓可以切出好几次发布，互不干扰；玩家装自己想要的那个，因为每个 zip 带自己
的 id。门禁发布的是 tag 点名的包，不是“仓库里的那个包”。

## id 是存档键

manifest 里的 `id`，会被引擎用来把一局存在 `save:<id>:<slot>`。所以同一个仓里的
两个包不能共用一个 id，已发布的 id 也不能改名：所有指向它的存档都会丢。第一次
发布前把 id 定死，然后别再动。替换的包拿一个新 id；旧的不用复用。

## 层指向什么

```json
{ "kind": "layer", "layer": "mod", "target": "sanguo", "requires": ["sanguo"] }
```

`target` 是层要改的那个包的 id——实践中是 `bundle`，因为一局只能从它开始。装配器
拒绝三种情况，各有自己的码：

- `V-33` —— 装配里的某个名字没装；
- `V-34` —— target 不在装配里、就是层自己，或 target 成环；
- `V-35` —— 两个层写同一个包的同一个字段。

一个层只指一个 target。要改两个包，就发布两个层。

## 起名：世界在前，用途在后，形态不进名字

| id | kind | 读起来是 |
| --- | --- | --- |
| `sanguo` | `bundle` | 底包故事 |
| `sanguo-cards` | `bundle` | 同一个世界，用牌玩 |
| `sanguo-content` | `layer`，`content` | 同一个故事，换一种讲法 |
| `sanguo-hard` | `layer`，`mod` | 同一个故事，更难 |

第一段是世界，所以一个世界的一切排在一起。第二段说这个包为玩家做什么，用玩家会
用的词。形态**不**进名字：`sanguo-cards` 是 bundle，`sanguo-content` 是层，只有
manifest 说得清。别用 `-layer`、`-bundle`、`-v2`、`-final`：id 是存档键，`-v2`
就是新包穿着旧包的名字。

## 界面怎么处理这些

一个 bundle 在包页上是单独一行，标题取它的 `names[locale]`。几个包共享一个
`collection`，就由一个世界行通向它们。层永远不单独占一行：它是 `target` 所指
那一行下面的一个勾选框，默认不勾，因为层改变的是玩家已经同意玩的那一局。

## 还没生效的东西

规划一族包之前先读这里：

- `target` 不是 bundle 的层，在构建装配时被 `V-44` 拒绝；
- `content`、`mod`、`assets` 生效；`genre` 与 `meta` 装了什么也不改；`profession`
  是 bundle 自己的数据（`data/factions.json`、`phases.ranks`、资源标签），所以
  `profession` 层没有东西可合并（`ADR-0016`）。

## 仓库不是契约的一部分

它的文件夹、README、测试和 `infra/` 都是你的；引擎从不看它们。形状只被两处强制
——你发布的压缩包，和玩家执行的安装——两处读同一套规则。所以一个仓可以放一个包
或十个包，也所以唯一需要提前规划的，是那一串 id。
