---
depends_on:
- "129-user-extension#0"
perf_phase: false
status: planned
---
> DONE-WHEN: Adapter case pinned; example round-trips; all tests pass on both backends.
> NEXT: none

# Type adapters

## Planned Work

- `.go` adapter metadata through reflect, semantic, validation (`ZIGO052`), abi-diff.
- Emit: skip the mirror, delegate conversions, spell the user type, add imports, force non-castable.
- Case, example, docs, CHANGELOG.

## Done When

- Adapter case pinned; example round-trips; all tests pass on both backends.
