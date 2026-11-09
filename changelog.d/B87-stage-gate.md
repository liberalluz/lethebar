### Added

- `infra/checks/check_lifecycle.py` — the lifecycle report's `missing` list is the
  verdict, and a warning is not a reason. The open batch's own exit record is
  exempt: `exit` writes it after the merge (B87).

### Changed

- The gate runs the lifecycle report and `pr_merge.py --self-test`, taking the
  check count from ten to twelve. A merged batch with no exit record, or a plain
  commit body that loses its `Batch:` line, now turns the gate red instead of
  relying on someone running the tools by hand.
