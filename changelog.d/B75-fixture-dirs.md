### Fixed

- `check_pack.py`, `check_guide.py` and `pack.py` make their self-test
  directories with a plain `mkdir` under `.test-tmp` and remove them
  themselves. `tempfile.mkdtemp()` stamps the directory with mode `0o700`,
  which on Windows replaces the access control entry it would have inherited,
  so under a restricted token the self-test died with
  `PermissionError: [WinError 5]` and left a directory behind that nothing
  could delete. Three such directories had accumulated in the checkout.
- `check_pack.py --self-test` and `check_guide.py` now fail when a fixture
  directory is still in `.test-tmp` when they finish, so the next leak is
  reported by the check that caused it instead of being found by hand.
