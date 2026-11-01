# ADR-0004 · Saves live in IndexedDB

## Context

Each plugin keeps its own save slots (three by default), and a save must survive a
reload, work offline, and stay namespaced per plugin. Packages can be several
megabytes, and a save payload grows with session state. The browser build must
write saves without a server.

## Decision

Store saves in **IndexedDB, accessed through the JS bridge**, keyed by plugin id
and slot number. The payload is JSON containing the schema version, plugin
identity, current node, progression state, RNG state and save time.

## Consequences

- No practical size ceiling compared with key-value browser storage, which matters
  once several plugins each hold three slots.
- Writes are asynchronous, so the save path must be wrapped and the UI must not
  claim success before the write resolves.
- The native build does not have IndexedDB; the store is therefore defined behind
  a persistence interface with a second backend added at v0.1.0.
- Quota and private-mode failures are normal outcomes and are surfaced through the
  warning channel instead of being swallowed.

## Rejected alternatives

- **`localStorage`.** A few megabytes, string-only, synchronous; three slots per
  plugin across several plugins makes the ceiling a real risk, and a failed write
  is easy to miss.
- **The engine's own config storage.** Convenient but opaque: no per-slot
  metadata, no inspection, and it ties the save model to one engine, which
  contradicts the neutral-JSON rule.
- **Cloud saves.** Out of scope for v0.0.0 and incompatible with the offline
  constraint as a default.
