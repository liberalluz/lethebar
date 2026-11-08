# Changelog

## v0.7.1 - 2026-11-08

### Fixed
- A layer ticked on the pack page now reaches the run: the story button carries the ticked set with it instead of starting the pack alone.
- A layer can no longer be opened as a story. Opening one leaves the pack page with `E-03` and no session, because a layer has no entry node of its own.

## v0.7.0 - 2026-11-08

### Added
- The pack page offers the layers installed against that pack. None of them starts ticked, so a player who never asks for one keeps the run the pack describes.
- Starting with layers ticked builds the run from the assembly of the pack and those layers, and the scene reads what the assembly resolved.
- A save records the set it was written with. Continuing rebuilds that set, not what happens to be ticked now, so resume means the run the player left.
- `docs/guide/repositories.md` says what a package is: the two `kind` values, why every run needs exactly one bundle, the six dimensions a layer can fill, the three refusals the assembler makes, and the naming rule that puts the world first and the form nowhere.
- `docs/guide/repositories.md` shows one repository holding two bundles and two layers, and says which row of the interface each one appears on.
- `docs/guide/mod-layer.md` walks a `mod` layer from folder to release: the manifest, the five inputs a mod may write, the two codes a clash produces, the four commands that publish it, how a player ticks it, and three checks that prove it changed a run rather than only that it installed.
- The guide index lists the page and points at it from the "several packs" way in.
- `TC-ASSEMBLY-003`: a save written in a layered run, replayed through the registry the way the interface does it, still refuses the disabled action and still reads the layer's on the ledger.

### Changed
- `docs/guide/pack-anatomy.md` sets the minimal manifest of a bundle beside the minimal manifest of a layer, and adds the three questions that tell them apart.
- `docs/guide/manifest.md` explains how `kind`, `layer` and `target` depend on each other, including the asymmetry that a `layer` on a bundle is ignored while a `target` on a bundle is refused, and closes with what this build does not honour yet.
- The guide index now describes `repositories.md` as covering the two kinds and the six dimensions, which it has done since `#119`.

### Fixed
- `check_pack.py`, `check_guide.py` and `pack.py` make their self-test directories with a plain `mkdir` under `.test-tmp` and remove them themselves. `tempfile.mkdtemp()` stamps the directory with mode `0o700`, which on Windows replaces the access control entry it would have inherited, so under a restricted token the self-test died with `PermissionError: [WinError 5]` and left a directory behind that nothing could delete. Three such directories had accumulated in the checkout.
- `check_pack.py --self-test` and `check_guide.py` now fail when a fixture directory is still in `.test-tmp` when they finish, so the next leak is reported by the check that caused it instead of being found by hand.
- An assembly now applies the `content` block a layer declares. `_apply_layer()` merged resources, actions, pools, cards and disabled names, and dropped content on the floor, so a published `layer: content` package installed, assembled, and changed nothing. The block is one object rather than a list, so a layer that declares it replaces the base package's block; a layer that declares none leaves it alone.
- `TC-CONTENT-002` covers the case: the same base package assembled without the layer reads its own cast and arc, and with the layer reads the layer's, while the nodes and the phase machine stay the base package's.
- Two ticked layers that write the same field are refused before a run starts, with the message the assembly produces rather than a generic failure.
- A save whose layer is no longer installed is refused with `E-02` and the name of the missing package, instead of opening a run that is missing a layer.
- A save that recorded a layer now replays it as a layer. `InstallRegistry.entry()` copies the manifest's `layer` and `target` onto the record it returns, so a run rebuilt from a save keeps the actions the layer disabled and the definitions it overrode instead of treating it as one more additive package.

## v0.6.1 - 2026-11-08

### Added
- `docs/guide/pack-anatomy.md`, `docs/guide/manifest.md` and `docs/guide/publishing.md`: what a pack is, what every manifest field means, and the six commands that turn a directory into a release.
- `templates/pack-min/`: a pack small enough to read in one screen that installs, walks one choice and saves.
- `infra/tool/docs/gen_guide.py`: rewrites the field and vocabulary tables from the const arrays in `app/core/manifest_schema.gd`; `--check` reports drift instead.
- `infra/checks/check_guide.py`: checks the tables, builds the template, runs the envelope check and installs the zip in a headless probe. Wired into the gate as the `guide` step.
- `docs/guide/bricks.md`: the eight bricks, each one named with the data file that turns it on and the engine file that reads it.
- `docs/guide/protocols.md`: the two protocols the engine implements, and a section saying that `cards.hand@1` is a capability rather than a third one.
- `docs/guide/errors.md`: every refusal code with the line that raises it and the sentence a player sees, generated from the source.
- `templates/pack-turn/`: a turn-based template with a menu, a limited run and two ranks, next to the linear one.
- `infra/checks/check_guide.py` now builds, installs and plays both templates, so a template that stops installing breaks the gate.
- `github.com/liberalluz/lethebar-pack-template`, a public template repository with the two release tools, the three-step author gate, and a working example pack. Its gate ran on the example before it was offered, so a new author starts from a repository that already builds, checks and publishes.
- `docs/guide/README.md`, the guide's front door: reading order, three ways in, and the two pages to read if you read only two.
- `docs/guide/repositories.md`, on a world repository that holds several packs: one folder per pack, one tag and one release per pack, the id as save key, and layers declared with `requires` and `target`.
- The minimal manifest in `docs/guide/pack-anatomy.md`, quoted whole so the smallest pack can be copied by hand.

### Changed
- `infra/tool/docs/gen_guide.py` fills five tables across four pages instead of two tables on one page; the brick and protocol tables fail the generator when the source loses a file or a protocol it describes.
- `docs/README.md` and the root README link to the guide, which shipped without an entry point.

## v0.6.0 - 2026-11-08

### Added
- `infra/tool/release/pack.py` builds a pack directory into a reproducible zip, writes a descriptor with the id, version, bytes, sha256, `specVersion` and engine range, and uploads both to a release (dry by default).
- `PackageLoader.import_url(url, expected_sha256, context, fetch)` installs a downloaded pack after checking its digest, and `PackageLoader.digest_of(bytes)` is the shared hash.
- `V-43` refuses bytes whose hash differs from the expected value, naming the url and both digests.
- `TC-NEUTRAL-001` builds a package inside the suite and walks install, play, save and resume on it, so the engine path is proved by a package the engine owns.
- A capability request form, so a package author can ask the engine for behaviour instead of being told to wait for a batch, and `docs/specs/capabilities.md` answers with one of three written outcomes.
- An install entry that takes a link as well as a file. `app/render/downloader.gd` fetches the bytes and `PackageLoader.import_url` hashes them before anything is written, so a truncated download stops at `V-01` and a wrong digest at `V-43`, both naming what disagreed.
- Three reported outcomes for an install: `installed`, `already` and `refused`. A refusal leaves the installed set untouched, and a link install with no digest is refused rather than trusted.
- `verify_web.py --min-packs N`: the browser check fails when the build offers fewer stories than asked for, which is how a batch that removes a story can prove the stories it kept still ship.
- `infra/ci/author-gate.yml`: the gate a pack repository copies into `.github/workflows/`, with its four steps in the order each one depends on.
- `infra/checks/check_author_gate.py`: the template is checked for shape, since the only thing that can be wrong with it here is a step that moved or vanished.
- `infra/checks/check_pr_body.py`: reads a pull request body by file or number and refuses one that lacks Summary, Impact, Verification, Risks or Self-check, that orders them differently, or that leaves a section empty.
- `batch.py pr <id> --translations-only`: redoes the pull request translations after the batch merged, for the case where only the translated body was wrong.
- `infra/tool/release/preflight.py`: six numbered items that say what a pack repository is missing before it publishes — manifest, version and contract, artifact, descriptor, release, and whether a browser can actually fetch the asset. Each failure names the command that fixes it, and the last item fetches the published zip over the network instead of assuming it is reachable.
- `pack.py publish --apply` creates the release when the tag has none. `gh release upload` only attaches files to a release that already exists, so the first publication of every pack used to fail with `release not found`.
- `pack.py` validates a pack before it builds any command: a descriptor with no id or version is refused, and nothing reaches `gh`.
- `infra/checks/check_pack.py` reads the archive a package publishes to and nothing else: `manifest.json` alone at the root, every other entry under `data/`, `assets/` or `i18n/`, no `..`, no absolute path, no symbolic link, no executable suffix, and caps on entry count and bytes. Ten negative cases run in `--self-test`, one per rule, and the gate runs them.

### Changed
- Nothing in a run changes: the new path ends in the same `import_bytes` every install already used.
- The suite asks whether a built-in story is staged before it opens one, and reports how many cases it skipped, so the four stories can move to a world repository without taking the engine's proof with them.
- `ADR-0010` now describes a package by three axes (form, dimension, trust), says what each kind of repository must never hold, and closes with the three misreadings the earlier wording invited.
- `infra/tool/release/pack.py self-test` writes its own two-file fixture in a temporary directory instead of reading a shipped story, so the tool that proves the release pipeline no longer depends on content that is scheduled for removal.
- `TC-COLLECTION-001` builds its two worlds from `sanguo` and `xiuxian`, and `TC-META-001` covers the two stories that remain.
- The pack list draws two entries where it drew one: `Install a pack (.zip)…` and `Install from a link…`.
- The probe reports `stories`, the count it read on the landing screen, so the check above has a number to compare.
- `infra/stage_builtin.py`: staging now removes an archive whose source directory is gone, names what it removed, and fails when a removal is blocked. `B59` shipped a deleted story for exactly one release because staging only wrote.
- `infra/checks/check_tree.py`: gains `--profile engine|world` and `--root`, and refuses an `app/builtin/*.zip` that no `content/builtin/<id>/` backs.
- `infra/checks/run_godot.py`: reads the suite's summary line and fails when more cases were skipped than `LETHEBAR_MAX_SKIPS` allows, so a green run has to mean something ran.
- `infra/tool/batch/config.json`: the tree check names the engine profile, and a `release-tool` step runs `pack.py self-test` before the translation check.
- `batch.py pr --prepare` no longer invents a body when `.batch/<id>/pr-body.source.md` is missing. It exits 1 and names the five sections the template asks for, instead of shipping the stand-in body that B58 carried into its pull request.
- Missing pull request translations are a failure now, not a note. A batch whose translation hook is not configured cannot prepare a pull request.
- `CARD_TYPES` matches the seven commit types the conventions list. `process` is gone from the tool; it was never a type, only a branch prefix, and `B57` and `B61` both wrote it because the tool accepted it.
- `infra/ci/author-gate.yml` says at the top that it is a template to copy into a world repository's `.github/workflows/gate.yml`, and `infra/checks/check_author_gate.py` refuses the file if that sentence is missing.
- `infra/tool/batch/config.json` runs the author-gate check right after the tree check.
- `docs/specs/git-conventions.md` says a batch card's type uses the seven commit types, and replaces the `pack/<space>/vX.Y.Z` line with the rule that each pack is tagged on its own and a repository version is bookkeeping only.
- `pack.py` reads the GitHub client from `LETHEBAR_GH` (default `gh`), which is what lets a test prove that the create runs before the upload.
- The docstring example tags a pack as `pack/<id>/vX.Y.Z`, matching the release section of `docs/specs/git-conventions.md`.
- `preflight.py` and `pack.py` share the reachability rule: an asset that answers without `Access-Control-Allow-Origin` is reported, because a browser install depends on that header and a terminal does not.
- `REQ-014` asks for one smoke story instead of a built-in 三国, `REQ-015` says the two worlds ship as external packages, and `REQ-034` describes the released package rather than one compiled into the engine.
- The shell cases that used to open 三国 now open `duel`, so the engine is still proven without a world: `TC-UX-001`, `TC-SAVE-002`, `TC-PKG-001`, `TC-INSTALL-001`, `TC-COLLECTION-001` and `TC-META-001`.
- The author gate is three steps now - `build` -> `check_pack` -> `publish` - and mentions no `infra/stage_packs.py`, no `--path app` and no `app/builtin`. A plugin repository is a project; only its archive is checked.
- `infra/checks/check_tree.py` stops having an opinion about an author's repository: the `world` profile is gone and `--profile` with it. The engine's own layout rules are unchanged.
- `ADR-0010` records the move: what may not exist is an executable entry inside a pack, not a build script in someone's repository.
- The cultivation pack is called `cultivation` everywhere. `SDD` section 10.2 lost the pinyin in both languages, `ADR-0007` names the pack the same way the repository does, and `ADR-0010` points at `lethebar-game-cultivation`.
- `ADR-0012` draws its worked example with `cultivation` instead of `xiuxian`, so the two-level menu example matches what a reader can install.

### Fixed
- Installing a world package used to fail with `V-03: already installed at 0.1.0; re-import that version or uninstall first`, because the engine shipped the same id at an older version and there is no uninstall control. With the built-in story gone, an external `sanguo` installs into a fresh engine.

### Removed
- The `jianghu` story, which demonstrated that a third pack could be written as data and then stayed as a dependency of every count in the specification documents, of every staging run, and of the release tool's own self-test.
- `TC-BUILTIN-003` and the case that opened the removed story, in both languages of the test plan and the test design.
- The engine no longer ships the 三国 and 修仙 stories: `content/builtin/` holds `duel` only, and both worlds arrive as packages from their own repositories. `TC-BUILTIN-001` and `TC-BUILTIN-002` left with them, and their assertions now live in the world repositories' gates as `TC-WORLD-001` and `TC-WORLD-002`.
- The save key of the built-in copy that `B65` removed is no longer readable: those keys were shaped `save:xiuxian:<slot>`. No published package ever used the pinyin.

## v0.5.0 - 2026-11-07

### Added
- A package may declare `view`, `density`, `cast` and `arc` in its manifest, and the scene honours them: the cast line above the text, the sparse readout without the situation, the dense readout with the arc stage and its turn.
- `V-40` refuses a `view` or a `density` the engine does not know, naming the field and the value.
- `V-41` refuses a cast with a repeated id or an empty name, and an arc whose turns are not ascending and unique.
- A package may declare `meta`: a pitch in one or more languages, an audience, a length in minutes and an optional icon, and the pack list shows the pitch and the length.
- `V-42` refuses an audience, a length, a pitch entry or an icon the engine cannot honour, naming the field.

### Changed
- The save payload carries the declaration, so a resumed run reads the way the saved one did.
- The three built-in stories declare who they are for in both languages.

## v0.4.0 - 2026-11-07

### Added
- An assembly entry may carry a `target` beside its id. A package that does so is a layer: it edits the package it names instead of adding another story, so one base can be played with and without the rule change it declares (REQ-042).
- `data/disable.json` lets a layer remove actions, pools, cards and resource definitions by id, which is the one thing a package could not say before.
- `V-34` refuses a layer whose target is not in the same assembly, a layer that sits on itself, a chain that returns to a package it already touched, and a package named twice.
- A layer package names the package it edits in its own manifest: `target` is required when `kind` is `layer`, and an assembly entry may still carry one that wins over the manifest.
- `V-35` refuses two layers that write the same field of the same target, naming both layers, the kind of field and its id.

### Changed
- `PackageLoader.assemble()` accepts either a package id or an `{id, target}` record and resolves the layer chain in list order, base first.
- A session copies the lists it is handed. It used to share the arrays held by the installed package, so appending an action for one run changed the package for the next one — the layer work would have made that visible, the fix belongs here.
- A package whose `kind` is not `layer` is refused with `V-23` when it declares a `target`, because that reads as a layer that forgot to say so.
- The story is clicked by the name the current screen shows, not the one read from the landing screen before the world narrowed the list.

### Fixed
- The browser probe walks the world screen before it picks a story. A repository cut by world opens a world list first, so the old probe waited for a pack list that never appeared and reported a missing session on every release build since v0.3.0.
- The probe now prefers a story whose picture actually reaches the scene band. A deck of cards declares one texture per face, and a picture count was being read as "the band will be visible".

## v0.3.0 - 2026-11-06

### Added
- `ADR-0012` gives a package an optional `collection` (`{id, names}`) and fixes the shelf as a world page above the pack list, skipped when only one world exists.
- `ADR-0013` gives a session an assembly: an ordered package list, three merge semantics, an acyclic layer chain, `V-33`–`V-35` for conflicts, and the assembly recorded in the save.
- `ADR-0014` records the four phases a mechanism mod passes through, from a field in its own package to a listed marketplace variant, and the hard line that a mod only changes what is declared.
- `cards.hand@1` — a package declares a hand, a small deck and its cards, and the engine deals, plays, discards and draws them.
- `app/core/hand.gd` — reads the declaration (`hand.size`, `hand.draw_per_turn`, `hand.reshuffle`, the `cards` table, the opening `deck`), deals the opening hand and refills it.
- `Session.play_card()` — spends the cost, applies the effects through the same clamping the rules use, discards the card, draws a replacement and advances the turn by one.
- `V-36`, `V-37`, `V-38` — a claimed `cards.hand@1` without a deck file, a card naming a resource the ledger never declares, and a deck naming a card the package never declares are refused at install with a message that names the missing thing.
- A fourth built-in story, `duel`, written only as data: a hand of four cards drawn from a deck of eight, two plain actions, ten turns with three ranks and one failure. It plays with no change under `app/core` or `app/render`, which is what the card capability was for.
- `TC-BUILTIN-004` in the test plan and the test design, in both languages: the opening hand, a played card, the refusal, the rank, the ending and a save that keeps the three piles.
- `infra/checks/check_commit_body.py --ref <commit>` judges a single commit. The range mode cannot see a squash merge: the commit lands on the default branch and no branch is ahead of it.
- `docs/specs/git-conventions.md` §2 states both rules: plain text wrapped at 72 columns, and the check that runs against `main` after a merge.
- A card may name a picture its package declares; the hand draws it beside the label at `CARD_ICON_SIZE` (REQ-037).
- `V-39`: a card naming an icon that no texture asset declares is refused at install, and the message names the missing path.
- `Shell.card_rows()` reports what the last scene drew for the hand, so the headless smoke test can assert on a picture without reading pixels.
- Six faces on the shipped `duel` cards, 64x64 PNG, one per card.
- A hand is laid out in rows of as many cards as the window fits, so a long hand wraps instead of pushing the card faces and the menu below the fold.
- The number of cards per row is measured from the window width (`Shell.hand_columns()`), so a resized window re-wraps the same hand.
- A card that shares a row has its label cut at `HAND_LABEL_CHARS` with an ellipsis; a hand that fits on one row keeps the whole label.
- `TC-HAND-001` covers the wrap: eight cards take more than one row at 600 px, every card is laid out once, a wider window needs fewer rows, and a short hand keeps its whole label.
- A reshuffle can ask the session for an order: `Hand.draw_into()` takes an optional callable and keeps play order when no callable is given, so the function stays a pure function of what it is handed.
- The session passes `_shuffle_cards()`, a Fisher-Yates pass over the run's own seeded generator, so one seed deals one order and another seed does not.
- A package may declare `collection: {id, names}`, the world it belongs to, and the landing screen offers worlds before packs (PR 85).
- A world title comes from the package that declares it and follows the interface locale; a world two packs word differently keeps one title, taken from the pack whose id sorts first.
- `PackageLoader.assemble()` resolves an ordered list of installed packages into the entries a session is built from, and refuses a name nothing installed provides with `V-33`.
- `Session` accepts `options.assembly`: the first package supplies the nodes, the phase machine and the entry, the rest may only add resources, actions, cards and pools.
- `TC-ASSEMBLY-001` opens one run from two packages and covers the merged view, the merged menu, the missing package and the duplicate key.

### Changed
- `ADR-0010` is cut by world, not by genre: a theme repository holds packs, a genre repository holds material (example, template, acceptance list), and neither holds code. The card battle now moves into `lethebar-game-sanguo`, not into a repository of its own.
- `ADR-0011` records `collection` and `layer`, resolves a composition before install rather than one file, and reviews by `kind`.
- The scene draws the hand above the action menu, keeps a card it cannot pay for on screen with the reason and disables it, and the reason names the resource that is short (`S-08`).
- `snapshot()` carries `hand`, `deck` and `discard` only when the package declares a hand, and a resume puts all three back before the scene is drawn.
- `infra/tool/merge/pr_merge.py` now flattens the body it writes: inline code and bold lose their markers and every paragraph is filled at 72 columns, so a rendered pull-request body no longer becomes a commit message full of backticks and one 880-character line.
- `--verify-only` applies the same rules, so the top commit of `origin/main` can be judged after a merge, which is the only moment a squashed message can first be read.
- The `card` asset slot is skipped by the scene band instead of being reported as an unknown slot.
- A package that allows a reshuffle now gets a shuffled deck instead of the discard pile in the order the cards were played. No package format field changed, and no package needs to be rebuilt.
- `start_game()` opens the world screen only when more than one world holds packs, so a repository with a single theme keeps its click count.
- A key that two packages both declare keeps the earlier package's value and leaves one `W-05` naming the key, instead of silently overwriting.
- A save records the assembly when a run was opened from more than one package, so a resumed run rebuilds the same set; a single-package save keeps its old shape.

### Fixed
- The five decision records that had lived only in a conversation now exist in the repository, so the model can be read instead of remembered.
- A pack that names a world with a malformed id or no titles is refused at install with `V-32` instead of showing up in a world nobody can name.

## v0.2.1 - 2026-11-06

### Changed
- `SaveStore.resume()` takes the locale as an option. The save keeps the run, not the preference, so a payload written before this change still resumes — in the package's text.

### Fixed
- A run resumed from a save slot reads in the locale of the interface instead of falling back to the package's own text, so an English interface no longer opens a Chinese scene after `Continue`.

## v0.2.0 - 2026-11-06

### Added
- A rule may carry `relations`, a list of `{from, to, add|value}` entries: the mechanics layer collects them and the session applies them, so the faction map still has one writer (`REQ-032`).
- `V-31`: a relation change that names an entity the package never declared, or carries something that is not a number, is refused at install.
- The save payload carries `factions`, so a moved relation survives a save and a resume.
- `Session.situation()` reads how a run stands: the turns left from the declared budget, the entity the others lean toward and the one they push against from the sum of the relations each receives, and the resource closest to its declared floor (`REQ-033`).
- The scene prints that reading as one more segment of the readout line, through `ui.turns_left`, `ui.leaning`, `ui.friction` and `ui.tight`, in both languages.
- Sanguo is a run now: twenty-four turns, four resources (grain, troops, coin, standing), five ranks from 校尉 to 大将军, three declared ways to lose and a menu of five actions, all as package data.
- The story declares three neighbours and rules that move the relation between them once the standing crosses a threshold, which is the first shipped use of `REQ-032`.
- The English table covers the opening scene, so an English session reads English from the first screen.
- A package table may now carry a `strings` section that names the labels a run is made of: `action.<id>`, `rank.<turn>`, `resource.<id>.<value>` and `failure.<index>`.
- The session looks those keys up when it builds the view, so an English run reads English in the menu, the rank, the labelled resources and the reason a run ended. The render layer did not change.
- Sanguo and Jianghu ship the new section, so both English runs are complete.

### Changed
- `Mechanics.apply()` returns a `relations` list next to `state` and `warnings`; packages that write no relation behave exactly as before.
- A section whose source is not declared is left out instead of being filled with a zero, so a story without factions or phases reads exactly as it did before.
- `SDD.md` §10.1 describes Sanguo as a run rather than a three-step sketch, and `TC-BUILTIN-001` now asserts the budget, the ranks, the menu, the relation, the mid-run save and one of the three losses.
- `V-22` measures the same keys. A package that ships a table for a locale must translate every action, rank, labelled value and failure it declares, because a table that covers the scene and forgets the menu is the half-translation the check already refused.

## v0.1.1 - 2026-11-06

### Added
- `infra/tool/merge/translate_body.py`: translate a prepared pull request body and mark the result as a machine translation; `LETHEBAR_TRANSLATION_FILE` supplies the translation where no API key is available.
- `infra/checks/check_translation.py`: refuse a batch whose prepared body has no translation, or whose translation predates the last edit.
- `V-27`: a package that asks for a capability this engine does not provide is refused at install, and the refusal names the capability (ADR-0008).
- `W-03`: a format 1.0.0 package that still names a capability without its major version installs with one warning, so nothing published before this batch stops working.
- `docs/specs/capabilities.md` now lists the twenty ids this build accepts, and the table is read back by the test instead of being copied.
- `V-28`, `V-29` and `V-30`: a package is held to an install-time envelope before the manifest is read, and every refusal names the value it measured.
- `app/core/package_limits.gd`: the limits and the pure helpers that read a PNG or JPEG header and a WAV duration, so the numbers live in one place.
- `TC-SAFE-001`: entries, paths, per-entry bytes, the unpacked total, picture edges and audio length are all exercised, and a package inside the envelope still installs.
- The landing screen says how large the first download is, once per profile, and asks the player to keep the tab open until it finishes (`REQ-031`).
- The page asks the generated service worker whether it kept the payload and publishes the answer as `window.lethebarCache` (`controlled`, `stored`, `error`, `ready`), so a failed cache write is visible in the interface.

### Changed
- `infra/tool/batch/config.json`: `translate` runs the new hook, and `translation` joins the gate as an eighth check.
- The `capabilities` field is versioned: `text` became `text@1`, `render.2d` became `render.2d@1` in the three built-in packages and in every test fixture.
- ADR-0009 now carries the numbers instead of promising them, and `SECURITY.md` says what the envelope is.
- The shell draws the first-visit sentence from the cache state rather than from a constant, so a build whose payload size changes says the new size.

### Fixed
- `infra/tool/merge/pr_merge.py`: a single-commit pull request whose subject is longer than the seventy characters GitHub keeps in `messageHeadline` began its body with the cut remainder; the message now comes from the local commit, and a payload that cannot be repaired is refused instead of used.

## v0.1.0 - 2026-11-05

### Added
- A package says which format it speaks, whether it is playable on its own (`kind: bundle`) or a piece another package requires (`kind: layer` with a `layer` name), and what it needs (`requires`), as ADR-0007 settles.
- The installer refuses a package whose `kind`/`layer`/`requires` are malformed (`V-23`) or whose requirement is missing or outside its range (`V-24`), and says which package and which version it wanted.
- The built-in stories declare format `2.0.0` with no requirements, so what players install is the shape the format asks for.
- A package can declare its numbers and their bounds in `data/state.json`, and a resource may map values to display text with `labels`.
- `data/rules.json` settles values in file order after the chosen action's own effects, so a rule reads what the effect just wrote.
- `V-14`: a rule that names a resource the ledger never declares is refused at installation, naming the resource.
- A package can declare an action menu in `data/actions.json`: costs, effects and `requires` are applied together, and an action whose requirement fails is listed as unavailable with the failing condition instead of vanishing.
- `data/phases.json` gives a run a length, ranks read from the turn number, and failure conditions whose reason is shown when they end the run.
- `data/checks.json` resolves dice checks from the session RNG and records the numbers that decided them under `state.checks.<id>`.
- `V-16`, `V-17` and `V-18` refuse a malformed menu, phase machine or check at install time.
- A package can declare item pools in `data/pools.json`: a draw takes the declared number of items and removes them unless the pool replaces them, and what is left travels in the save so a reload cannot re-roll it.
- `data/factions.json` declares directed relations between factions, with the state names supplied by the package through `thresholds`.
- `V-19` refuses a pool that lists an item twice or draws past its size without `replace`; `V-20` refuses a relation that points at an undeclared entity, and `W-02` reports a pair that disagrees in direction without rewriting it.
- A package can declare `clock.per` and a rule can read the engine tick, so content that grows per turn no longer has to fake a counter with resources.
- `TC-CLOCK-001` asserts the tick, both advance modes, the save, and the two refusals.
- A package that declares actions is playable: the scene draws one button per action, keeps an unavailable action visible and disabled with its reason, and shows the turn and the rank.
- `TC-SCENE-001` covers the six lines: the run opens with an empty choice list, every action is a button, an unavailable one is disabled, an action advances the turn and the rank, an ended run shows why and offers nothing, and a package without actions renders as before.
- An action can wait on a relation state the package declares, and on an item a run has already drawn; both read the same numbers the scene shows.
- An action can draw from a pool as part of itself, so the draw and the action's own effects commit in one step and the item unlocks whatever waited on it.
- Validation codes V-25 and V-26 refuse a condition that names a state or an item the package never declared, and a draw that names a pool it never declared.
- Test case TC-WIRE-001 covers the two gates, the joined draw, a save and resume, and both refusals.
- A third built-in story, `jianghu`, written only as data: a ledger of three resources, four actions, one pool, a phase machine with three ranks and a failure condition, and an English table.
- Test case TC-BUILTIN-003 installs that story from the shipped build and plays it to an ending, so a whole new kind of story is shown to run on the bricks the engine already ships.

### Changed
- A package that still declares `1.0.0` installs and carries one `W-01` warning; from v0.2.0 on it is refused.
- Sanguo now keeps `power` and `standing` as numbers with labels (`兵微将寡`, `初露锋芒`, `名动诸侯`) instead of writing a string from a rule.
- Values are clamped into their declared `min`/`max` after both effects and rules; a choice that would overflow stops at the bound instead of failing.
- A save now carries the turn number and the per-action counters, so a restored run keeps its rank and its used-up actions.
- A save now carries what is left of every pool and the order the session RNG fixed on its first draw, so a restored run draws the same way it would have.
- The tick travels in the save payload, so a resumed run continues counting from where the player left instead of starting over.
- A run no longer ends merely because the node it lands on offers no choices when the package declares a phase machine; the phase machine's failure condition or turn limit ends it instead, which is what a menu-driven package needs.
- The readout names the items a run has drawn, because the player can now act on them.
- The build now stages three packages instead of two; `chars.txt` grows to cover the new story's text.
- The browser check waits for that state instead of sleeping two seconds before reloading, and it counts restored slots from the cross-pack list on the landing screen rather than from whichever pack it happened to open.
- `CONTRIBUTING.md`, `CONTRIBUTING.zh-CN.md` and `docs/specs/git-conventions.md` now name `--out` as the way to produce the `--body-file` argument, and record both ways it has gone wrong: the subject repeated in the body (`#38` to `#45`) and U+FFFD from a redirect (`#46`).
- `CONTRIBUTING.md` and `CONTRIBUTING.zh-CN.md` point at `docs/specs/git-conventions.md` §2 and §4 instead of repeating the merge rules, which had already grown three paragraphs of history.

### Fixed
- A save now reports itself as pending until the storage layer says it has nothing left to flush, so the slot screen says "Saving…" before it says the slot is saved and a reload cannot outrun the write. Installing a package passes through the same gate.
- `pr_merge.py --body-only` prints the body alone, so `gh pr merge --body-file` no longer puts the subject on the first body line. `#38` to `#45` were merged with the whole message and each carries that duplicate; they are left as they are, and §4 of `git-conventions.md` now says which flag feeds which argument.
- `pr_merge.py --body-only --out <file>` writes the merge body to a file itself, so the text never passes through a shell pipe that decodes UTF-8 as the local code page; `#46` lost an em dash to that step and was amended.
- `infra/checks/check_commit_body.py` refuses backticks, `**bold**` and `__bold__` in a commit body outside a fenced block: a commit message is never rendered, so the markers reached the reader as characters. `0bf59cd` carried ten backticks until it was amended.

## v0.0.2 - 2026-11-04

### Added
- The `修仙` pack now carries an English table: an English reader meets English scene text and English choice labels in the second built-in story, not Chinese.
- `TC-I18N-001` in the suite: the shipped Xiuxian pack is played in English and must leave no Chinese ideograph in its entry scene or its labels.

### Changed
- `xiuxian`'s manifest declares `defaultLocale`, `locales` and `names`, so it is listed as `Cultivation` on an English landing page and as `修仙` on a Chinese one.
- The font subset is rebuilt from the full Noto Sans SC with `infra/build_font.py`, so the repertoire is reproducible instead of being whatever the last person happened to cut.
- The web payload grows from 3,473,468 to 4,142,764 bytes (`index.pck`), the only file that changes: the engine payload is byte-identical and keeps its cache name.

### Fixed
- An ideograph from CJK extension A (`U+3400-U+4DBF`) now draws as a glyph instead of a box: the shipped font covers that block as well as the BMP block it already covered.

## v0.0.1 - 2026-11-03

### Added
- A package may declare `defaultLocale`, `locales` and `names`, and carry one table of text per language under `data/i18n/<locale>.json`. The Sanguo pack now ships English text for every node and choice.
- `V-22` refuses a package whose declared locale is unsupported, has no table, or leaves a node text or a choice label empty.
- `app/i18n/en.tsv` and `app/i18n/zh_CN.tsv`, the two interface catalogues.
- a language switch on the landing screen; the choice is stored and survives a reload.
- A pack can declare pictures and sound, and a scene now draws them: one wide slot for a scene (or its background fallback) and one narrow slot for a portrait. The bytes are read out of the package once, at import, and decoded only when a scene asks for them.
- `sanguo` ships a painted scene and a short theme, so the first story is no longer text only.
- `infra/tool/merge/pr_merge.py`: builds the message for a squash merge and checks the commit one leaves behind. One commit keeps its own subject and body, so a single-commit pull request needs no arguments; more than one needs `--why` and `--batch`, because there is no single reason to take from them.
- `python infra/tool/merge/pr_merge.py --verify-only` reads the top commit of the default branch. Nothing read that commit before: the commit-body gate only looks at `origin/main..HEAD` on a branch, so a missing `Why:` on `main` stayed invisible.

### Changed
- A new session plays in the language the interface is in, and falls back to the package's own text when the package carries no table for it.
- The pack list shows the pack's title in the current language when the manifest supplies one.
- The picture band now takes what the text and buttons leave over instead of a fixed share of the window, so a longer English scene keeps every button on screen.
- A published build no longer re-downloads the 39.5 MB engine payload when it did not change: `index.wasm` and `index.pck` now sit in their own caches, named after a digest of their bytes, while the page and its scripts keep the timestamped cache.
- Staging the built-in packages writes fixed timestamps into the zip entries, so packing the same sources twice produces the same bytes and a story build can keep its package cache.
- every interface sentence now comes from `Locale.text()`, so `app/render` holds no user-visible text of its own.
- The picture band collapses to zero height when a pack declares no asset, so text-only books keep exactly the layout they had before pictures existed.
- The browser check now fails when a picture band pushes a button out of the window, and it proves an imported pack was written to storage before it blames the cache for losing it.
- `CONTRIBUTING.md` and `CONTRIBUTING.zh-CN.md`: the merge step says to run that check after merging, and says what a multi-commit pull request has to pass to `gh pr merge`.

### Fixed
- The worker declared `PAYLOAD` without `PAYLOAD_PREFIX`, so the first update that had old payload caches to clear would have thrown inside `activate` and left the player on the previous worker.
- Installing a new worker no longer prefetches the payload: that download competed with the engine's background write of the player's own `user://` data, which is how an imported pack could disappear before it reached IndexedDB.
- `pr_merge.py --verify-only` now reports a commit that sits on the default branch without its `(#<number>)` suffix. It used to pass any commit whose pull request was not named, which is how a merged subject lost `(#36)` for a few minutes.
- `pr_merge.py --show` appends the number only once. A subject that already ended in `(#<number>)` came out as `(#36) (#36)`.

## v0.0.0 - 2026-11-02

### Added
- Import a plugin package from a zip file; a package with a missing field, an out-of-range engine version or an unknown protocol is rejected with a coded reason (B1).
- Play a `linear@1` flow to its ending, with a snapshot that repeats byte for byte when the same seed and the same choices are replayed (B2).
- Play `turn_based@1` rounds and the built-in `sanguo` package: three decision rounds to an ending, with power supply read out per round (B3).
- Keep three save slots and imported packages across a reload; a save written by an unknown schema is refused with a reason instead of being migrated (B4).
- A first-time player can open the app, pick the shipped `sanguo` pack, play it to the end, save to a slot and load that slot back — the shell now renders the landing screen, the plugin list, the session screen with its mechanic readout, and three save slots.
- The web build draws that first screen in a browser: the smoke probe reloads it three times and reports the median time until the screen settles.
- A package that fails validation is refused with its code shown to the player, and the pack list still works afterwards.
- A second built-in genre ships: `xiuxian` plays a five-scene segment on `linear@1` and shows how far along the segment the player is (`step 2/5`), which is the first use of the `progress` mechanic.
- The shell lists whatever has been staged into `res://builtin/` instead of naming one package, so a new genre appears without touching the render layer.
- The web build installs a service worker that caches the whole payload on first load, so a reload with the network off still starts a game.
- The smoke check now drives the build with the network off: it reloads, starts a game, and reads back the save slot it wrote before going offline.
- The pack list offers "Install a pack…": a player picks a `.zip` from their own disk and it is validated and installed like a built-in one (V-01…V-09), with a refusal showing its code and leaving the installed packs alone.
- On the web build the file arrives through an `<input type="file">` injected next to the canvas; nothing is uploaded and a session still makes no network request. Desktop builds open a native picker.
- The smoke probe installs a real package through that button and asserts it is still installed after an offline reload, which closes the last unproven half of `TC-OFF-004`.
- `app/render/fonts/NotoSansSC-Regular.woff2`: one Noto Sans SC subset (SIL OFL 1.1) owned by the render layer and shared by every pack, so a pack carries its text and never a font. Coverage is `U+4E00-9FFF` plus punctuation, ASCII and Latin-1; rare ideographs outside it still fall back to boxes.
- A headless check that fails when a character a shipped pack can show — or a character the shell puts on screen — has no glyph in the font the project ships. String assertions passed while every Chinese line was unreadable, so the coverage is now asserted on characters rather than trusted.
- `PROBE_SHOT=<path>` on the smoke probe writes the first scene as a PNG, for the parts of the picture a person has to read.
- `Continue` on the landing screen lists every saved run in this browser - each row names its story, its slot, a preview of the scene and the time it was written - and opens that pack exactly where the player stopped. It only appears when something is saved.
- The web smoke check now clicks the first screens instead of only screenshotting them: the probe presses "New game" and a pack with real mouse events and fails if the canvas does not answer.
- The product version lives in `app/project.godot` (`application/config/version`) and the shell reports it as `lethebarState.version`, so a release has one number to keep in step instead of three.
- Export the project for the web with `infra/export_web.py`, and load the exported build in a headless browser with `infra/verify_web.py` (no batch; the browser pipeline was previously unproven).

### Changed
- Saves and imported packs live in the engine's own storage (IndexedDB on the web build) instead of memory, so they survive a reload.
- A session is proven not to touch the network by counting browser requests during play, not by grepping the source for an HTTP client.
- The landing screen is a way in again, not a menu: one line says what the game is, then `New game` leads to the stories. Listing the stories on the landing screen made every visit start with a choice before the player saw the game.
- The pack list shows each pack's own name and hides the protocol identifier: `sanguo — turn_based@1, 0.1.0` read like a turn-based strategy game.
- The save screen says what a slot holds ("Saving keeps your place in this story"), and an unused slot reads "nothing saved yet" instead of "empty".
- The shell names the current screen in the window title and, on the web build, in a `window.lethebarScreen` global, so a browser driver can tell which screen a click landed on without reading pixels.
- The landing screen shows the version at the end of its one line, which makes it obvious which build a phone is running.

### Fixed
- Imported packs disappeared after a reload because the stored packages were never restored; they are restored at boot now.
- The screen's text column grew past the window when the text wrapped, which pushed every button, including "New game", below the fold.
- Pack text renders in the browser. The engine shipped its built-in font, which has Latin glyphs only, so every Chinese string in `sanguo` and `xiuxian` drew as a box; a player could start a game and see nothing readable.
- Opening a download link on the site (for example `/lethebar/test-pack.zip`) showed the game instead of the file: the offline document fallback answered every top level navigation. Only a directory or `index.html` URL now gets the document.
- Opening the site offline now works. The generated service worker cached `index.html`, but a player navigates to the directory URL (`/lethebar/`), and the cache lookup compared whole URLs, so every offline reload fell through to the network. On iOS Safari that surfaced as "FetchEvent.respondWith received an error: TypeError: Load failed" instead of the game.
- The smoke check now navigates to the directory URL like a player does, so the offline phase would have caught this; it previously navigated to `/index.html` and passed.
- The Continue list showed each save's time in UTC, so a save made at 14:20 in UTC+8 read `06:20`. It now shows the player's own clock.
- In a narrow window the save slots pushed `Save` and `Load` past the right edge, so a player could not save or load at all. Each row now wraps its text inside the width the window leaves for the two buttons, and the stored preview is clipped to 24 characters with an ellipsis instead of taking the first 40 characters of the scene.

### Removed
