---
completed_at: "2026-09-07T15:33:56Z"
perf_phase: false
status: done
---
> DONE-WHEN: Public API and normalized behavior, root suite and example generated checks pass; documentation and commits complete.
> NEXT: none

# Initial Work

## Planned Work

- Rename function/functions/value and enumeration authoring methods to func/funcs/val/enumType without compatibility aliases, as requested; migrate all callers and current guides.

## Done When

- Public API and normalized behavior, root suite and example generated checks pass; documentation and commits complete.

## Implementation and validation

- Renamed public Scope methods and Context forwarding declarations with no old-name aliases. Updated all active Zig callers, negative fixtures, thirteen examples and current documentation. Historical research/review records remain historical.
- `zig test src/root.zig -lc`: 16/16 passed, including Context normalized comparisons and plugin option tests.
- `zig build test --summary all`: 318/318 steps and 765/765 tests passed.
- All thirteen examples passed go-check, with purego-go-check where available and -Dpurego for tagged-union. No generated artifacts changed.
- git diff --check passed; existing fixtures validate diagnostics through the renamed API.
