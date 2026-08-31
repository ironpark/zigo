---
completed_at: "2026-08-31T18:49:34Z"
depends_on:
- "49-49-skip-empty-generated-go#0"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test` and `zig build check` pass.
> NEXT: none

# Generation formats its own Go output

## Planned Work

- Add `--gofmt <path>` to the `gen` subcommand in `cli.zig`, defaulting to
  `gofmt` on `PATH`, matching the flag `doctor` already accepts.
- In `main.zig`, after `generate` returns, run the formatter once over the
  output directory with `std.process.run`, the way `doctor.zig:88` already
  probes it. `gofmt` recurses into a directory, so one call covers whatever set
  of files generation produced.
- A missing or failing formatter fails generation with a message naming the
  binary, because `doctor` already tells the user that generated Go is
  gofmt-formatted and a missing binary is not optional.
- Leave `generate` itself untouched: it stays a pure writer with no child
  process, so its in-file tests remain hermetic and offline.
- In `build.zig`, delete `formattedGoSources` and the five path constants that
  feed it, pass `--gofmt` through to the `gen` run, and use `generated_dir`
  wherever `go_sources_dir` was used.

## Done When

- `zig build test` and `zig build check` pass.
- `zig build go` in an example produces Go byte-identical to what the per-file
  `gofmt` pipeline produced, so no committed artifact changes in this phase.
- `build.zig` contains no `_type_gen.go` / `_errors_gen.go` / `_helpers_gen.go`
  path literal and no `gofmt` `Run` step.
