# GOALS

## Problem and the end result from the user's point of view

zigo generates Go bindings for Zig libraries. Plans 185, 186 and 187 moved the
Go-specific knowledge behind three seams: the IR's `go` namespace, the
`targets.Target` interface, and the plugin contract's `output_targets` filter.
Each of those plans was verified by generated output not moving, which proves
the refactoring was safe but proves nothing about whether the seams actually
carry a second language.

This plan finds out. A user points `--target rust` at the same
`bindings.zig` that produces Go today and gets a Rust crate: `extern "C"`
declarations over the same C ABI shim and the same C header, plus a safe public
wrapper. The end result is one runnable example that mirrors
`examples/00-quick-start`, whose `cargo test` and demo both actually run and
print `2 + 3 = 5`.

The other half of the result is a truthful map of where the seam held and where
it creaked, written down for whoever extends this past the minimum.

## Measurable goals

- `targets.byName("rust")` returns a `Target`; `src/gen/targets/rust.zig` holds
  it and no caller in `src/gen/validate/**`, `src/gen/report.zig`,
  `src/gen/abi_diff.zig` or `src/reflect/**` is edited to accommodate it.
- The Rust emitter reuses `emit/shim.zig`, `emit/header.zig` and the panic
  source unchanged; every byte of Rust it writes is new.
- Three type shapes work end to end: scalars, `[]const T` slice parameters,
  and error unions surfacing as `Result<T, E>`.
- `cargo test` and `cargo run` pass in the new example, run for real on this
  machine, with `2 + 3 = 5` in the demo output.
- All 74 generator cases regenerate byte-identically, plus new Rust cases whose
  goldens are committed.
- `git status --short` over `examples/*/go`, `examples/*/zigo` and
  `tests/generator_cases` is empty after the per-example runs.

## Supported scope and non-goals

Supported: free functions; scalar parameters and returns; `[]const T` slice
parameters; error-union returns over scalar payloads; the shared C ABI shim,
panic source and C header; static linking; `rustfmt`.

Non-goals, each for a stated reason:

- **Cancellation** (`context.Context`, `SemanticFn.cancel`, `cancel_error`).
  Research blocker 2: Rust has no direct counterpart and the IR concept is
  Go-shaped. Needs its own design. The example deliberately avoids it.
- **Callbacks, `std.Io` streams, tagged unions, opaque handles, materialized
  result trees.** Past minimum. `handle` -> `Drop` is the obvious next step and
  is left as the hand-off, not attempted here.
- **Dynamic loading** (`libloading`, purego's counterpart). Static only.
- **A Rust plugin contract.** Plan 187 made `Plugin.output_targets` default to
  `&.{"go"}`, so existing plugins simply do not run for a Rust target. Nothing
  to do.
- **Refactoring the Go emitter.** `src/gen/emit/**` is Go's, measured at 0%
  reuse. The Rust emitter is a sibling tree, not a parameterization. The one
  exception is named in CONTEXT and argued there.
- **`--gofmt` and `zigo doctor` keeping their Go names.** User-visible tooling
  surface; plan 186 already decided this.

## Reference source / commit / license

Branch `rust-minimal-backend` off `main` at `c92ec348`, the commit that closed
plan 187. Prior art inside this repository:

- `docs/.agent/research/rust-target-feasibility.md` -- layer-by-layer reuse
  measurements and the six blockers.
- `docs/.agent/plan/186-186-target-interface/PLAN.md`, section
  `What a Rust Target Implements` -- the per-member checklist this plan works
  through, including the one interface change it predicted would be needed.
- `docs/.agent/plan/185-ir-target-namespacing/` -- the `go` IR namespace whose
  sibling this plan adds, and the migration convention.
- `docs/.agent/plan/187-plugin-contract-targets/` -- how the contract carries a
  resolved target.

No external source is copied.

## Completion criteria for the whole plan

- Every phase `done`, each independently verified.
- Root `zig build test --summary all` green.
- `scripts/update-generator-cases.sh` leaves `tests/generator_cases` clean.
- All thirteen existing examples pass
  `zig build test go-check go-lib abi-check go-coverage` and `go test ./...`,
  with no change to any committed `.go`, `.zig`, `.h` or `semantic.json`.
- The new example passes its own Zig tests, `cargo test` and `cargo run`.
- `zig fmt --check src build build.zig` clean; `cargo fmt --check` clean in the
  new example.
- A `[Unreleased]` entry in `CHANGELOG.md`.
