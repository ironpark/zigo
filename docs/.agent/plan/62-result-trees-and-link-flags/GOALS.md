# GOALS

## Problem and the end result from the user's point of view

Two remaining dogfooding findings. (a) `configuration.md` only says system
library and framework link info is forwarded to `#cgo LDFLAGS`; in fact only
`-l<name>` is emitted regardless of `use_pkg_config`, `addLibraryPath`,
`rpaths`, and `include_dirs` are dropped, framework `weak` is lost, and the
`cgo_flags` override still gets system `-l` and framework lines appended. A
static cgo link against a pkg-config library in a non-default prefix fails
without a manual override. (b) A read-only metadata tree (`Probe`, 15 fields,
three levels of nested `(ptr, len)` arrays) must be redesigned as opaque
handles with one native call and one `RLock` per field. After this plan the
link rules are documented and pkg-config libraries propagate through cgo's own
`#cgo pkg-config:` directive; out-only value structs may carry string and array
fields that the generated Go deep-copies in one call; the value-struct
append ABI policy is documented with its hazard and, if adopted, gated.

## Measurable goals

- `configuration.md` states the exact propagation rule for each `std.Build`
  link input and what `cgo_flags` replaces versus keeps.
- `linkSystemLibrary` with `use_pkg_config != .no` emits `#cgo pkg-config:
  <name>`; `.no` keeps `-l<name>`; `lib_paths` become `-L` entries.
- An out-only `extern struct` with `(ptr, len)` byte fields and `(ptr, count)`
  nested struct arrays generates a single-call deep copy on both backends.
- `abi-check` policy for trailing value-struct field appends is documented; any
  compatible classification is opt-in and refused outside static cgo.

## Supported scope and non-goals

In scope: build.zig flag collection, emit of link directives, docs; a new
`direction`/`repr` axis for out-only value structs with pointer-bearing fields,
release integration from plan 61 phase 4, recursive copy emission; abi_diff
policy option and docs.

Non-goals: in-direction pointer-bearing structs (Go → native trees); mutable
trees; propagating `rpaths` into generated files (documented as unsupported);
purego link directives (none exist by design).

## Reference source / commit / license

Repository at HEAD after plan 61. cgo `#cgo pkg-config:` directive per Go's
`cmd/cgo` documentation. MIT.

## Completion criteria for the whole plan

All phases done or explicitly deferred with the deferral recorded in
`limitations.md`; docs, goldens, and examples updated; committed.
