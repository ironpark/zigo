---
depends_on:
- "87-field-accessors#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Example Go tests pass on cgo and purego; full verification loop green.
> NEXT: none

# Emit accessors on both backends

## Planned Work

- Shim bodies for getters and setters; C header entries; Go methods with lifecycle guards on cgo and purego; `abi-diff` classification.
- Generator case with expected snapshots; example extension with Go tests reading and writing a nested field on both backends.
- `docs/bindings.md` section "필드 접근자" and CHANGELOG `### Added`.

## Done When

- Example Go tests pass on cgo and purego; full verification loop green.
