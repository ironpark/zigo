# GOALS

## Problem and the end result from the user's point of view

`addGoBindings` takes one `target` and one `link`, and the cgo raw package
emits a single unqualified `#cgo LDFLAGS:` line naming one archive in one
install directory. A project that ships a Go module for several platforms has
to run one `zig build` per target into separate prefixes, and the committed Go
tree can only link the last one built. purego already handles this through
`//go:build` tagged loaders; cgo has no equivalent.

After this plan, a caller lists `targets` on `addGoBindings`. One generation
produces one Go tree whose cgo block carries a `#cgo <goos>,<goarch> LDFLAGS:`
line per target, each naming that target's archive under
`<library_dir>/<goos>_<goarch>/`. `zig build go-lib` builds and installs every
target's native library, and `go build` with any listed `GOOS`/`GOARCH` links
the matching archive with no extra configuration.

## Measurable goals

- The emitter renders a qualified `LDFLAGS` line per target when given a
  target list and stays byte-identical to today's output when given none.
- A build with `.targets = &.{ host, other }` installs two archives in two
  target-named subdirectories and the committed raw package references both.
- Single-target callers see no change in generated files or install layout.

## Supported scope and non-goals

Supported: `.cgo_static` and `.cgo_dynamic` with a target list, per-target
volatile link inputs, doctor reporting `native` when any listed target matches
the host. Not supported: mixing purego with a target list (purego already
covers this via runtime loading), per-target `cgo_flags` overrides, and
prebuilt `.static_path` archives in a multi-target module graph (they cannot be
retargeted, so the build panics with a clear message).

## Reference source / commit / license

Own code. cgo directive constraints are documented in `go doc cmd/cgo`
(`#cgo GOOS,GOARCH LDFLAGS:` lists build constraints before the verb).

## Completion criteria for the whole plan

`zig build test` passes, a new generator snapshot case pins the multi-target
cgo block, a build-level smoke proves two targets install side by side, and
`docs/configuration.md`, `docs/limitations.md`, README and CHANGELOG describe
the option.
