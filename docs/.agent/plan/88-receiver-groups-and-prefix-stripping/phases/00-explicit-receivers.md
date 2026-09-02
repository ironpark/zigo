---
perf_phase: false
status: planned
---
> DONE-WHEN: Group and per-entry receivers produce Go methods with stripped names on both backends; verification loop green.
> NEXT: none

# Explicit receivers and group prefix stripping

## Planned Work

- Extend the metadata schema; reflect explicit receivers with pointer type check and a new diagnostic; expand groups into per-function entries with the stripped default name.
- Tests in `walk.zig`/`validate.zig`; generator case; example extension (an example with an opaque type and a root-level function taking that type); docs and CHANGELOG.

## Done When

- Group and per-entry receivers produce Go methods with stripped names on both backends; verification loop green.
