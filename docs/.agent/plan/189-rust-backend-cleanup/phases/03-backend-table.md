---
depends_on:
- "189-rust-backend-cleanup#2"
perf_phase: false
status: in-progress
---
> DONE-WHEN: `grep -n "targets.rust" src/gen/generator.zig` matches only the backend table
> NEXT: none

# Make the backend a table and finish the name-override seam

## Planned Work

- Replace the `Target.name` string compare in `generator.zig` with a
  generator-owned backend table: one row per target carrying its optional
  `unsupportedIssues` slot and its tree-append function, looked up by name with
  no default language. Assert at comptime that every entry of `targets.all` has
  a row. Explain in the comment why the table cannot live on `Target.vtable`:
  `targets` is a leaf both `emit` and `emit_rust` import, so pointing it at
  emitter tables is a build-graph cycle.
- Add `VTable.setNameOverride`; `go.zig` supplies `setGoName`, `rust.zig`
  supplies `setRustName`. `validate.zig` calls `target.setNameOverride`, using
  the `target` already in scope on the enclosing line.
- Call `appendArtifacts` from the Rust tree as the Go tree does, letting
  `registry.runs` gate it through `output_targets`, so a plugin's artifacts are
  not dropped without a message.

## Done When

- `grep -n "targets.rust" src/gen/generator.zig` matches only the backend table
  row.
- Adding a target to `targets.all` without a backend row fails to compile.
- `zig build test` passes and generated Go output does not move.
