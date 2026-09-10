---
depends_on:
- "188-minimal-rust-backend#3"
perf_phase: false
status: in-progress
---
> DONE-WHEN: `cd examples/13-rust-quick-start && zig build test rust-check rust-lib abi-check`
> NEXT: none

# Build integration and a runnable example

## Planned Work

- Extract the shared reflector and module-graph setup out of `addGoBindings`
  into `build/modules.zig`, with `addGoBindings` calling it. This is the Go-side
  edit CONTEXT argues for; it must be behaviour-preserving, which the thirteen
  examples check.
- Add `addRustBindings` to `build.zig`: the shared reflection and semantic
  capture, `generate --target rust`, the shim static library and header install
  (identical to Go's), publish and `check` over the manifest, and
  `RustBindings.addStandardSteps` registering `rust`, `rust-check`,
  `rust-lib`, `abi-check` and `cargo`-driven `rust-test`.
- `examples/13-rust-quick-start/`, mirroring `examples/00-quick-start`:
  - `src/root.zig` with `add(a, b) -> i32` verbatim from the quick start, plus
    `sum(values: []const i32) -> i64` and `divide(a, b) -> MathError!i32` so the
    three supported shapes are all exercised. No cancellation, no callbacks, no
    handles.
  - `src/bindings.zig` declaring the three.
  - `build.zig` calling `addRustBindings`.
  - `rust/Cargo.toml` and `rust/build.rs`, hand-written, linking the installed
    static archive -- the counterpart of the Go examples' `go.mod`.
  - `rust/src/lib.rs` and `rust/src/raw.rs`, generated and committed.
  - `rust/tests/` covering all three functions, and `examples/` or a `src/bin`
    demo printing `2 + 3 = 5`.
  - `README.md` in the shape the other examples use.
- Run it: `cargo test` and the demo, for real, and paste the actual output into
  the phase outcome and the final report. Compiling without running is the
  failure this phase exists to rule out.
- `CHANGELOG.md` `[Unreleased]` entry.
- Update `docs/.agent/research/rust-target-feasibility.md`: mark step 4 done and
  record what the seam actually cost, replacing the estimate with the measured
  line counts.

## Done When

- `cd examples/13-rust-quick-start && zig build test rust-check rust-lib abi-check`
  passes, and `(cd rust && cargo test && cargo run --example demo)` prints
  `2 + 3 = 5`. The real output is recorded in the phase outcome.
- `cargo fmt --check` clean in the example; `git status --short examples/13-rust-quick-start`
  empty after `zig build rust`.
- All thirteen pre-existing examples still pass their full step list and
  `git status --short` over them is empty -- the `build/modules.zig` extraction
  is behaviour-preserving.
- `scripts/update-generator-cases.sh` leaves `tests/generator_cases` clean.
- Root `zig build test --summary all` green; `zig fmt --check src build build.zig`
  clean.
- `CHANGELOG.md` has the `[Unreleased]` entry; the research document's step 4 is
  marked done with measured numbers. Committed.
