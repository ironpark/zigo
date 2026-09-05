---
completed_at: "2026-09-05T20:15:21Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test` passes with the new case and all existing snapshots
> NEXT: none

# Emitter and CLI target list

## Planned Work

- Add `CgoTarget` and `cgo_targets` to `emit.Options`, `generator.Options`,
  `cli.Generate`, and the test runner's `CaseOptions` (JSON list of
  `{goos, goarch}`).
- Parse a repeatable `--cgo-target <goos>/<goarch>` flag in `cli.zig`;
  reject malformed or duplicate pairs.
- In `raw.zig`, emit the qualified per-target `LDFLAGS` lines when the list is
  non-empty; keep the unqualified line otherwise and when `ldflags_override`
  is set.
- Add `tests/generator_cases/scalar_multi_target` (cgo, two targets) with
  its expected output and register it in `build/tests.zig`.
- Add unit tests in `emit.zig` and `cli.zig` for the rendered block and flag
  parsing.

## Done When

- `zig build test` passes with the new case and all existing snapshots
  unchanged.
- `zigo generate --cgo-target darwin/arm64 --cgo-target linux/amd64` produces
  two qualified `LDFLAGS` lines.
