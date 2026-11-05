# Security

## Reporting

Do not open a public issue for a vulnerability. Contact the maintainer privately
with:

```text
affected version
reproduction
impact
suggested fix
```

## Handling

- Acknowledgment within a reasonable time.
- Fix in a private branch, release, then disclose.
- Never commit credentials, signing material, or customer data.

## Package envelope

A package is data, never code, and it is held to these limits when it is
installed (constants in `app/core/package_limits.gd`, decision in ADR-0009):

- archive 8 MB, 500 entries, one entry 4 MB unpacked, 32 MB unpacked in total;
- paths relative and inside `[a-z0-9._/-]`, no `..`, no backslash;
- pictures at most 4096 px on an edge, audio at most 2 MB and 60 seconds.

Exceeding one refuses the install with `V-28`, `V-29` or `V-30` and names the
value that was measured, so an author can fix it without guessing.
