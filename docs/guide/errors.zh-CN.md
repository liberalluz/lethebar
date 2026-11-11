# 当引擎说不

[English](errors.md) · 简体中文

引擎每一次拒绝都带一个码。码是值得读的那部分：它点名检查，检查点名你要打开的
文件。

一共四族，出现的时机不同。

| 族 | 什么时候出现 | 关于什么 |
| --- | --- | --- |
| `V-xx` | 安装包时，什么都还没写 | 包本身：manifest、数据文件、信封 |
| `M-xx` | 读 `data/rules.json` 时 | 一条读不懂的结算规则 |
| `S-xx` | 玩的时候，执行动作或选择时 | 这一局：节点不存在、动作付不起、选择不提供 |
| `SAVE-xx` | 写或读一个槽位时 | 存档：没东西可存、槽位满、来自另一个 schema 的存档 |

`V-xx` 会中止安装，所以抛出它的包不会被存下，也不会出现在列表里。`M-xx` 在读
规则时抛出，也在安装期间。`S-xx` 和 `SAVE-xx` 出现在运行中的游戏里；它们以一句
短话给玩家看，从不让这一局崩掉。

## 每个码，以及在哪抛出

下表由源码生成；英文页是源头，这一页是译文，可能落后一次发布。中间一列是抛出
该码的引擎文件与行；最后一列点名 `data/...` 时，那就是作者要打开的文件。

| 码 | 抛出位置 | 它说什么 |
| --- | --- | --- |
| `M-01` | `app/core/mechanics.gd:38` | 规则缺少 set 子句 |
| `M-02` | `app/core/mechanics.gd:77` | when 子句必须是对象，而不是… |
| `M-03` | `app/core/mechanics.gd:110` | set 子句必须是对象 |
| `S-01` | `app/core/session.gd:143` | 协议…没有实现 |
| `S-02` | `app/core/session.gd:162` | 节点…不存在 |
| `S-03` | `app/core/checks.gd:38` | 没有名为…的检查 |
| `S-04` | `app/core/session.gd:256` | 没有名为…的动作 |
| `S-05` | `app/core/session.gd:260` | 原因 |
| `S-06` | `app/core/session.gd:468` | 池…不存在 |
| `S-07` | `app/core/session.gd:282` | 池…不存在 |
| `S-08` | `app/core/session.gd:325` | 资源….… |
| `S-09` | `app/core/session.gd:309` | 手里没有名为…的牌 |
| `SAVE-01` | `app/core/save_store.gd:14` | SAVE-01 |
| `SAVE-02` | `app/core/save_store.gd:15` | SAVE-02 |
| `SAVE-03` | `app/core/save_store.gd:16` | SAVE-03 |
| `SAVE-04` | `app/core/save_store.gd:17` | SAVE-04 |
| `SAVE-05` | `app/core/save_store.gd:18` | SAVE-05 |
| `SAVE-06` | `app/core/save_store.gd:19` | SAVE-06 |
| `SAVE-07` | `app/core/save_store.gd:20` | SAVE-07 |
| `SAVE-08` | `app/core/save_store.gd:21` | SAVE-08 |
| `V-02` | `app/core/package_validator.gd:90` | message |
| `V-03` | `app/core/package_validator.gd:97` | 必须匹配 [a-z0-9-]+ |
| `V-04` | `app/core/package_validator.gd:149` | specVersion |
| `V-05` | `app/core/package_validator.gd:522` | 期望形如 >=4.3.0 <5.0.0 的范围 |
| `V-06` | `app/core/package_validator.gd:533` | protocol |
| `V-07` | `app/core/package_validator.gd:540` | entry |
| `V-08` | `app/core/package_validator.gd:660` | 声明的资产在包里缺失：… |
| `V-09` | `app/core/package_validator.gd:545` | 必须是正整数 |
| `V-14` | `app/core/package_validator.gd:554` | ledger.json |
| `V-16` | `app/core/package_validator.gd:358` | actions.json |
| `V-17` | `app/core/package_validator.gd:365` | phases.json |
| `V-18` | `app/core/package_validator.gd:369` | checks.json |
| `V-19` | `app/core/package_validator.gd:379` | pools.json |
| `V-20` | `app/core/package_validator.gd:384` | W-02 |
| `V-21` | `app/core/package_validator.gd:586` | clock |
| `V-22` | `app/core/package_validator.gd:673` | defaultLocale |
| `V-23` | `app/core/package_validator.gd:170` | message |
| `V-24` | `app/core/package_validator.gd:221` | requires |
| `V-25` | `app/core/package_validator.gd:419` | actions.json |
| `V-26` | `app/core/package_validator.gd:446` | actions.json |
| `V-27` | `app/core/package_validator.gd:194` | capabilities |
| `V-31` | `app/core/package_validator.gd:617` | 规则里的 relations 必须是数组 |
| `V-32` | `app/core/package_validator.gd:117` | id 必须匹配 [a-z0-9-]+ |
| `V-36` | `app/core/package_validator.gd:463` | hand.json |
| `V-37` | `app/core/package_validator.gd:513` | hand.json |
| `V-38` | `app/core/package_validator.gd:473` | hand.json |
| `V-39` | `app/core/package_validator.gd:493` | hand.json |
| `V-40` | `app/core/package_validator.gd:243` | manifest.json |
| `V-41` | `app/core/package_validator.gd:265` | manifest.json |
| `V-42` | `app/core/package_validator.gd:305` | manifest.json |

## 按码该打开什么

码告诉你是哪个文件，句子告诉你文件的哪一部分。

- `V-01` 到 `V-06`、`V-27`、`V-39` 到 `V-42`：`manifest.json`。字段缺失或拼错，
  或它点名了一个引擎没有的协议、能力、视角、密度、图标、受众。
- `V-14` 到 `V-21`、`V-25`、`V-26`、`V-31`：某个数据文件点名了哪里都没声明的
  资源、动作、实体、状态或池。句子会说清是哪个。
- `V-22`、`V-30`、`V-43`：包自身的形状——某个语言没有文件、这个引擎不说的格式、
  对不上的摘要。
- `V-33`：装配点名了一个没装的包。
- `V-34`、`V-35`：层指向了不该指的东西，或两个层写了同一字段。
- `V-45`：两个生效的层带了同一个资产路径。句子点名两个层和路径；这一局不会开始。
- `V-47`：`persist` 表太大、类型不对，或没声明 `persist@1`；消息点名列或原因。
- `V-36` 到 `V-38`：`data/hand.json`。没有牌堆的手牌、未知资源、发不出的牌堆。
- `S-01` 到 `S-09`：这一局。节点或动作不存在、付不起，或在这里不提供。
- `SAVE-01` 到 `SAVE-08`：槽位。没东西可存、槽位越界、空槽位、来自另一个 schema
  或另一个包的存档。

## 玩家看到什么

`S-xx` 与 `SAVE-xx` 的句子由引擎组装，按写好的样子显示，值填进去：`S-05` 读作
“`farm` is not available: not enough grain”。`V-xx` 在安装时显示，就在它说的字段
或文件旁边，所以玩家读到的那行，就是作者需要的那行。

码是稳定的，永不翻译：码是作者去搜的东西。
