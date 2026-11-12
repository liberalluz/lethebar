# Cutting a release

The batch process is in `docs/specs/git-conventions.md` and the Nebula skills;
this page is the release itself, in the order it has to happen. It is the page
`README.md` points at.

1. **Collect the fragments.** Every `feat` or `fix` batch adds one file under
   `changelog.d/`. Check them against the planned version:

   ```text
   python infra/tool/release/release.py --check --version v0.9.0
   ```

2. **Write the changelog** and delete the fragments:

   ```text
   python infra/tool/release/release.py --write --version v0.9.0 --date 2026-11-12
   ```

3. **Move the version strings**, all of them, in one commit:
   `app/project.godot`, `README.md`, `README.zh-CN.md`, `docs/guide/publishing.md`
   and `docs/guide/publishing.zh-CN.md`.

4. **Regenerate the guide tables** with `python infra/tool/docs/gen_guide.py --write`
   and run the checks the release batch always runs: `check_guide.py`,
   `check_language.py`, the suite, and `batch.py check`.

5. **Merge the release batch** as a normal pull request. The README status line
   is part of that diff.

6. **Tag the release commit** and push the tag:

   ```text
   git tag -a v0.9.0 <commit> -m "Lethebar v0.9.0"
   git push origin v0.9.0
   ```

7. **Publish the notes and the evidence.** The player-facing notes live in
   `../lethebar-docs/product/release-notes/v0.9.0.en.md`; `publish.py` reads them
   and refuses a tag that is not the engine version:

   ```text
   python infra/tool/release/publish.py --check --version v0.9.0 --docs-root ../lethebar-docs
   python infra/tool/release/publish.py --apply --version v0.9.0 --docs-root ../lethebar-docs
   ```

8. **Export and push the web build** from the tag, into a `gh-pages` worktree:

   ```text
   python infra/export_web.py --output <gh-pages worktree>
   ```

9. **Freeze the baseline**: `baseline_hash.py --write`, add the row to
   `docs/baselines.md`, and merge that as its own pull request.

10. **Write the exit record** (`records/live/Bxxx-exit.md`), run
    `check_records.py`, and commit the records repository.
