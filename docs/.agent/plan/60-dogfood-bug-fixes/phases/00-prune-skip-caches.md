---
completed_at: "2026-09-01T20:31:49Z"
perf_phase: false
status: done
---
> DONE-WHEN: Regression test passes; `zig build test` green; committed.
> NEXT: none

# Prune and check skip build caches

## Planned Work

- In build.zig PublishGeneratedGo prune walk and src/gen/sync_check.zig, skip
  `.zig-cache` and `zig-out` directory entries at any depth during the walk.
- Add a regression test (build/integration or unit as fits the existing test layout)
  proving a marker-bearing `.go` file under `go_dir/.zig-cache/...` survives prune and
  is not reported obsolete by `zigo check`.

## Done When

- Regression test passes; `zig build test` green; committed.
