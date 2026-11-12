### Fixed

- The phone can install a pack. The picker asks the platform for its document
  picker instead of drawing a desktop window, the link dialog asks for an
  address only and opens a long-press menu with paste, copy, cut and select
  all, and the export stages the built-in pack before it exports.

### Changed

- A link install without a digest trusts the transport; the package still has
  to pass every check in `import_bytes`, and a digest that is given is still
  compared.
