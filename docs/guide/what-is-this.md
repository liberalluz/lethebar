# What is this?

English · [简体中文](what-is-this.zh-CN.md)

You write one zip. A player installs it and plays one run. There is no code in it.

## What you write

```
my-story.zip
├── manifest.json     what the pack is called, where a run starts
├── data/
│   ├── nodes.json    scenes: who appears, what the choices are, where they lead
│   ├── state.json    the numbers: money, stamina, trust
│   ├── actions.json  buttons: farm, send a gift, leave
│   ├── phases.json   turns, chapters, when a run ends
│   └── rules.json    what changes after what
├── assets/           pictures and sound
└── i18n/             the words, in each language
```

`nodes.json` is the story. Everything else is what the story can do: what can be
spent, what can be chosen, when the run is over, what changes when it does.

## How a run works

1. A player installs your pack from the packs page.
2. The engine opens the first scene and draws its words and choices.
3. The player picks one; the engine applies its effects and moves to the next scene.
4. At a boundary, `phases.json` and `rules.json` decide what is added, what is
   spent, and whether the run ends.
5. The player saves; next time the run continues where it stopped.

## What you do every day

Write scenes, tune numbers, replace art. That is the whole loop.

## What you can make

| What you make | What the player gets |
| --- | --- |
| a whole story | installs it and starts on the first page |
| an addition to someone else's story | the same run, told with another view, density or cast |
| a numbers patch | the same run, with other costs and other rewards |
| a look | the same run, with other pictures and sound |
| another story in the same world | another pack, on the same page |

## What you cannot do

- **A new kind of play.** Card battles, real-time fights, a map you walk: the
  engine has no step for them, so a pack that asks for one does not install.
- **Change someone else's story.** An addition can change how a story is told,
  not what happens in it.
- **Put code in the pack.** A pack is data; the engine is the only code.

## Where to read next

`pack-anatomy.md` for the shape of a pack, `manifest.md` for every field,
`bricks.md` for what each data file can say, and `publishing.md` for the six
commands that build, check and publish one.
