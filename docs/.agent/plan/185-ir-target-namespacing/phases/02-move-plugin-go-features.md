---
depends_on:
- "185-ir-target-namespacing#1"
perf_phase: false
status: planned
---
> DONE-WHEN: `SemanticFn` declares no Go-specific field outside `go`.
> NEXT: none

# Move the Go standard-library features

## Planned Work

- Move `SemanticFn.iterator` and `SemanticFn.implements` onto `FnGo` as
  `iterator` and `implements`. Both name Go standard-library shapes —
  `iter.Seq` and the four `io` interfaces — so they belong in the namespace even
  though the `implements` and `iterator` built-in plugins own them.
- Repoint the phase 0 accessors and the `implements` and `iterator` plugins in
  `src/gen/plugins/` at the nested fields.
- Update the `iterator` comparison in `src/gen/abi_diff.zig` and confirm it still
  reports an added, removed or renamed iterator wrapper as a contract change.
- Extend the version-1 parse test to cover both fields.
- Regenerate snapshots and review the diff.

## Done When

- `SemanticFn` declares no Go-specific field outside `go`.
- The `abi_diff` tests covering iterator changes pass unchanged in behaviour.
- The regenerated diff touches `semantic.json` only.
- `zig build test go-check abi-check go-coverage --summary all` passes.
