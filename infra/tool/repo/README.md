# Repository policy

`infra/tool/repo/apply_policy.py` checks or applies the `repoPolicy` block in
`.nebula-scaffold.json`.

```bash
python infra/tool/repo/apply_policy.py --check
python infra/tool/repo/apply_policy.py --apply
```

The adapter is GitHub-only. It checks the repository visibility and the default
branch protection settings; `--apply` updates both. Changing a repository from
private to public requires `--confirm-public`.

GitLab is recorded in the scaffold but is not applied by this adapter. The
policy stays provider-neutral so a GitLab adapter can be added later without
changing the scaffold format.
