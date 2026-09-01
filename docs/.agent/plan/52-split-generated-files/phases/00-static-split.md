---
completed_at: "2026-09-01T10:49:35Z"
perf_phase: false
status: done
---
> DONE-WHEN: Regenerated example 03 (no unions) shows the new file set with no union or
> NEXT: none

# Per-file writer plumbing and static split (enums, handles, runtime)

## Planned Work

- Refactor `emit.zig` so each public-package section renders into its own
  buffer with its own import computation, then flushes to per-concern paths:
  `<pkg>_enums_gen.go`, `<pkg>_handles_gen.go`, `<pkg>_runtime_gen.go`.
  Tagged-union content stays temporarily in the runtime file's writer or the
  existing path to keep this phase reviewable.
- Fold `<pkg>_helpers_gen.go` content into the runtime file and remove its
  path helper.
- Apply the no-empty-file rule per new file; update `generator.zig`
  file-presence tests and golden fixtures.

## Done When

- Regenerated example 03 (no unions) shows the new file set with no union or
  empty files and no `helpers_gen.go`; `gofmt -l` is clean file-by-file.
- `zig build test` passes; examples 03 and 10 compile and their tests pass.
