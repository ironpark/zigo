---
depends_on:
- "190-rust-handles-and-buffers#4"
perf_phase: false
status: planned
---
> DONE-WHEN: The live-bytes assertion passes, which is the only evidence that `Drop`
> NEXT: none

# Prove it in the example, and hand it on

## Planned Work

- Extend `examples/13-rust-quick-start` with an opaque type exercising all
  three shapes: a constructor, a `*T` method, a `*const T` method, a borrowed
  view, and a caller-owned buffer return. Keep the existing scalar, slice and
  error-union functions so the example still mirrors the quick start.
- Add integration tests: the handle frees itself (assert against a live-bytes
  counter that returns to zero after the wrapper is dropped, which is the
  observable proof `Drop` ran), the borrowed view reads through, the buffer
  derefs without copying.
- Extend the demo so `2 + 3 = 5` still prints and the new shapes print beside
  it.
- Run everything for real: `zig build test rust-check rust-lib abi-check
  rust-coverage`, then `cargo test`, `cargo clippy --all-targets -- -D
  warnings`, `cargo fmt --check` and the demo. Paste the actual output into the
  phase outcome. Compiling without running is the failure this phase exists to
  rule out.
- `CHANGELOG.md` `[Unreleased]`, and update
  `docs/.agent/research/rust-target-feasibility.md`: strike items 1 and 2 off
  the hand-off list, replace the estimate with the measured line count, and
  record which creaks this plan closed and which it left.

## Done When

- The live-bytes assertion passes, which is the only evidence that `Drop`
  actually reached the native destructor rather than merely compiling.
- `cargo test`, `cargo clippy --all-targets -- -D warnings`,
  `cargo fmt --check` and the demo all pass, with real output recorded.
- `git status --short examples/13-rust-quick-start` empty after `zig build
  rust`.
- All thirteen Go examples still pass with no drift; 77+ generator cases clean;
  root tests green; `zig fmt --check` clean.
- CHANGELOG entry present; the research document's hand-off list reflects what
  is left. Committed.
