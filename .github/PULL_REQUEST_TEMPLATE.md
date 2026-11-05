## Summary

<!-- one sentence: what changed and why -->

## Impact

<!-- one behaviour; name the main files; a platform gap belongs here -->

## Verification

**Environment**: E1 headless assertions / E2 Chrome / E3 device — say which evidence came from which layer.

**Commands and output** — paste the command and the lines that decide the outcome, verbatim. Do not paraphrase, and do not keep this placeholder. Write "rest omitted" for long output.

```text
$ <the command you ran>
<paste the lines that decide the outcome>
```

**Test design** — which assertion, what made it red, what the red looked like, how it was restored. For a docs-only change say there is no behaviour change and why that is acceptable.

**Not verified** — what has no evidence here and why; a platform gap is named under Impact.

## Risks

<!-- what is most likely to break, and how to roll back -->

## Self-check

- One batch, one behaviour: <batch id, or none with the reason>
- Commit bodies carry `Why:` and `Batch:`: <yes, or checked by check_commit_body.py>
- No secret or build output is committed: <checked by check_tree.py>
