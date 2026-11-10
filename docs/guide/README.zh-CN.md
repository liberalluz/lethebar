# 作者指南

Guide v1.0.0。十页，讲怎么写一个包：一个装数据的 zip，引擎读它、做判断、画出来。
不需要引擎源码，也不假设你读过别处。

## ① 先读这里

[这是什么？](what-is-this.zh-CN.md) —— 引擎是什么、你写什么、一局怎么跑、一个包
做不到什么。先读这一页，其余都是细节。

## ② 写一个包

| 页面 | 回答什么 |
|---|---|
| [pack-anatomy.zh-CN.md](pack-anatomy.zh-CN.md) | 一个包是什么、里面能放什么、安装时发生什么 |
| [manifest.zh-CN.md](manifest.zh-CN.md) | 每个字段是什么意思、有哪几个版本、什么会被拒绝 |
| [bricks.zh-CN.md](bricks.zh-CN.md) | 一个包能打开的八种机制 |
| [protocols.zh-CN.md](protocols.zh-CN.md) | 两种协议，以及为什么第三种推进方式是一种能力 |
| [mod-layer.zh-CN.md](mod-layer.zh-CN.md) | 改一个已发布包的数值与成本，从头到尾 |
| [repositories.zh-CN.md](repositories.zh-CN.md) | 一个仓放多个包、两种形态与六个维度、怎么起名 |

## ③ 发布

| 页面 | 回答什么 |
|---|---|
| [publishing.zh-CN.md](publishing.zh-CN.md) | 怎么构建、检查、打 tag、发布 |
| [errors.zh-CN.md](errors.zh-CN.md) | 每个拒绝码、玩家看到的那句话、该打开哪个文件 |

## 模板仓与可复制的仓库

- `templates/pack-min/` —— 能装能玩的最小包，在
  [pack-anatomy.zh-CN.md](pack-anatomy.zh-CN.md) 里整棵贴出
- `templates/pack-turn/` —— 同一个故事，加上菜单、动作和阶段时钟
- `github.com/liberalluz/lethebar-pack-template` —— 已经带好工具、门禁和一个可跑
  示例的仓库；点 **Use this template**

## 这些页不是规范

当它与 [`docs/specs/controlled/`](../specs/controlled/) 里的受控文档冲突时，受控文档
为准，这一页就是有 bug —— 这也是 [errors.zh-CN.md](errors.zh-CN.md) 的码表由源码
生成的原因。
