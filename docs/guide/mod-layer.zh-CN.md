# 一个 mod 层，从头到尾

一个 `mod` 层改一个 bundle 已经声明过的数值和成本。它不添加故事：节点、入口
节点和阶段机都还是底包的，因为一局有两个开头就不成一局。它能做的是让同一个
故事玩起来不一样——更紧的经济、多一个动作、被人拿掉的一张牌。

这一页带它从一个空文件夹走到发布，再说明怎么证明它在一局里真的生效，而不只是
装上了。

## 文件夹与 manifest

```
your-world-repository/
└── packs/
    └── sanguo-hard/
        ├── manifest.json
        └── data/
            ├── state.json      它重写的资源
            ├── actions.json    它添加的动作
            └── disable.json    它移除的动作
```

能装且生效的最小层：

```json
{
  "id": "sanguo-hard",
  "version": "1.0.0",
  "specVersion": "2.0.0",
  "kind": "layer",
  "layer": "mod",
  "target": "sanguo",
  "requires": ["sanguo"],
  "engine": ">=4.7.0 <5.0.0",
  "name": "Three Kingdoms, harder",
  "defaultLocale": "en",
  "protocol": "turn_based@1",
  "capabilities": ["text@1", "ledger@1"],
  "mechanics": ["grain", "coin", "troops", "standing"],
  "entry": "placeholder",
  "saveSchema": 1,
  "assets": []
}
```

三个字段让它成为层：`kind`、`layer`、`target`。`target` 是它要改的 bundle 的 id；
`requires` 说要用它必须先装什么。`protocol` 和 `entry` 只是因为格式还要求才重复；
没人读层的 `entry`，它也不需要 `data/nodes.json` 里有节点（`V-07` 只问 bundle）。

如果 manifest 声明了 `locales`，`data/nodes.json` 里的每个节点，都要在每个
`data/i18n/<locale>.json` 里有一条非空条目，以节点 id 为键。`{"strings": {...}}`
这样的表什么都过不了；安装会被 `V-22: data/i18n/en.json has no entry for node <id>`
拒绝。不带节点的层，完全不需要 `locales`。

## 它能改什么

| 输入文件 | 效果 | 限制 |
|---|---|---|
| `data/state.json` | 整个资源被**替换**：上下限、初值、标签 | 只能是底包已声明的资源；新名字被跳过 |
| `data/actions.json` | 动作被**添加** | 底包已用的 id 会被 `W-05` 拒绝，底包保留 |
| `data/pools.json` | 池被**添加**，连同内容 | 同样的重名规则 |
| `data/hand.json` | 牌加入手牌，`size`、`draw_per_turn`、`reshuffle` 填空缺 | 同样的重名规则 |
| `data/disable.json` | `{"actions": [], "pools": [], "cards": [], "resources": []}` 把那些名字从这一局移除 | 不存在的名字被忽略 |

它**不能**改 `data/nodes.json`、`data/phases.json`、入口节点或协议。那些属于底包，
一个试图改它们的层是设计问题，不是配置问题。

两个层碰同一个字段，会在会话开始前被拒绝（`V-35`），提示会点名两个层和那个
字段。两个层添加不同的动作，可以共存。

## 构建、检查、发布

四条命令与其他页相同，在仓库根目录运行：

```bash
python infra/tool/release/pack.py build packs/sanguo-hard
python infra/checks/check_pack.py dist/sanguo-hard-1.0.0.zip
git tag pack/sanguo-hard/v1.0.0 && git push origin pack/sanguo-hard/v1.0.0
python infra/tool/release/pack.py publish packs/sanguo-hard --tag pack/sanguo-hard/v1.0.0 --apply
```

tag 里带包名，所以一个仓可以发布一个底包和三个层，彼此的发布互不干扰。压缩包里
是 `manifest.json` 和 `data/`，从来不是包着它的那个仓库。

## 玩家最后怎么用到它

层永远不会单独占一行。在包页上，它是 `target` 所指那一行下面的一个勾选框，默认
**不勾**，因为层改变的是玩家已经同意玩的那一局。勾上再开始，这一局就由底包加上
勾选的层拼出来。

存档记下这个装配。重载时，同样的层会回来，即使现在勾的是别的东西；如果其中某个
已经被卸载，读档会被 `E-02` 拒绝，提示点名缺失的包，不会半加载。

## 证明它生效了

装上不是证明；一局才是。三个检查，按顺序：

1. **一个只有这个层能产生的数字。** 把底包的初始粮食写进层的 `state.json`，改成
   别的——`40` 改成 `25`——然后勾上层开一局，读故事下面那一行。不勾是 `40`，
   勾了是 `25`。
2. **一个只有这个层声明的动作。** 把 `levy` 放进 `data/actions.json`，勾上层，
   动作菜单多一个按钮。取消勾选，它就没了。
3. **移除。** 把一个底包动作放进 `disable.json`，勾上层，那个按钮从菜单里消失，
   其余照常。

然后存档、刷新浏览器、继续：同样的数字和同样的菜单应该回来，因为存档带的是
装配，不只是底包 id。

发布前先做第一个检查。一个装上、勾上、什么都没改的层，和一个能用的层长得一模
一样，直到有人去读那个数字。
