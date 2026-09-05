---
completed_at: "2026-09-05T20:24:17Z"
depends_on:
- "122-multi-target-cgo#0"
perf_phase: false
status: done
---
> DONE-WHEN: A scratch project with `.targets` for the host and one cross target runs
> NEXT: none

# Build integration for several targets

## Planned Work

- Add `build_options.goTarget` with tests covering the desktop matrix and an
  unsupported combination.
- Add `Options.targets: []const std.Build.ResolvedTarget = &.{}` to
  `addGoBindings`; the effective set is `target` plus `targets`, deduplicated
  by GOOS/GOARCH, and rejected for `.purego`.
- Generalize `hostReflectionModule` into a retarget clone that keeps prebuilt
  inputs out with a panic naming the object, and use it to build the shim
  library and static link inputs per extra target.
- Install each target's library (and Windows implib) into
  `<library_dir>/<goos>_<goarch>/` in multi-target mode; pass
  `--cgo-target` per target to the generator.
- Extend `PublishCgoLinkFlags` to write one qualified line per target.
- Doctor gets `native` when any effective target matches the host.
- Expose the per-target install steps and paths on `GoBindings` and make
  `go-lib`/`update` depend on all of them.

## Done When

- A scratch project with `.targets` for the host and one cross target runs
  `zig build go` and installs both archives under target-named directories.
- The committed raw package's cgo block lists both targets and `go build`
  on the host links the host archive.
- Existing examples build unchanged.
