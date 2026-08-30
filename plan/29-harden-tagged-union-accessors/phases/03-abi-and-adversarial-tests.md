---
depends_on:
- "29-harden-tagged-union-accessors#2"
perf_phase: false
status: planned
---
> DONE-WHEN: ABI unit tests and all Zig/Go/example/stale/ABI checks pass with documented compatibility and concurrency contracts.
> NEXT: none

# ABI classification and adversarial matrix

## Planned Work

- Classify append-only variants as additive while removals and existing tag/name/payload/symbol changes remain breaking.
- Expand fixtures for empty/mutable slices, custom names, multiple unions, normalized collisions, invalid widths, and cleanup.
- Update generated artifacts, CI-facing docs, and run the complete repository/example matrix.

## Done When

- ABI unit tests and all Zig/Go/example/stale/ABI checks pass with documented compatibility and concurrency contracts.
