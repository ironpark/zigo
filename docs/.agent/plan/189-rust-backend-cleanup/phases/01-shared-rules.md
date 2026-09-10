---
depends_on:
- "189-rust-backend-cleanup#0"
perf_phase: false
status: planned
---
> DONE-WHEN: `zig build test` passes.
> NEXT: none

# Give the shared rules one definition and drop the unused surface

## Planned Work

- Move `libraryPathEnvironmentAlloc` to `src/gen/naming.zig` beside
  `functionSymbolAlloc`; have both target vtables call it. Keep the reason in
  the doc comment: the variable names a deployment artifact, so two targets
  binding one library must agree. Replace the agreement test with one that
  covers the single rule.
- Delete `rust.generatedFileNameAlloc` and `rust.publicFunctionNameAlloc`,
  neither of which has a production caller; point the file-name test at
  `target.generatedFileNameAlloc` as the other target tests do.
- Delete `naming.camelWithInitialismsAlloc`, which has no caller but its own
  test; restore `camelAlloc`'s body to pass `go_initialisms` directly.
- Drop `"handle"` from `rust.reserved_locals`, which renames a parameter the
  generated bodies never collide with, and which the doc comment three lines
  above already contradicts.

## Done When

- `zig build test` passes.
- `scripts/update-generator-cases.sh` leaves `tests/generator_cases` clean.
- `libraryPathEnvironmentAlloc` has one definition.
- `pascalWithInitialismsAlloc` is the only `WithInitialisms` entry point.
