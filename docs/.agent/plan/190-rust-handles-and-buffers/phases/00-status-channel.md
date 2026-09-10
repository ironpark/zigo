---
perf_phase: false
status: planned
---
> DONE-WHEN: `tests/generator_cases/rust_checked/expected/src/lib.rs` shows the
> NEXT: none

# Separate the status channel from the declared error set

## Planned Work

- Give `raw.Shape` two distinct facts where it has one: whether the call has a
  status channel (`origin.@"return" == .error_union`) and whether the binding
  declares errors for it (`function.errors.len != 0`). Name them so a reader
  cannot conflate them again.
- A call with a channel and no declared errors returns its payload directly
  and panics on a non-zero code. Add `raw::panic_native(operation, code) -> !`,
  `#[cold]`, which reads the message through the existing
  `caught_panic_message` accessor and explains in its doc comment which codes
  can reach it and why each is a bug rather than a condition.
- Fix `public.hasErrors`: `error.rs` is emitted when any *declared* error code
  exists, which is what makes `Error` reachable. Confirm that a program with a
  status channel and no declared errors now emits no `error.rs` and no
  reference to `Error`.
- Add `tests/generator_cases/rust_checked/`: one function with a narrow-integer
  parameter and no declared errors, plus one with both a narrow-integer
  parameter and a declared error set, so the two spellings sit side by side in
  one golden.
- Check the whole refusal list for other shapes that reach a promoted empty
  error set today, and either cover or refuse each. This is the phase where
  that audit belongs, because the concept it depends on lands here.

## Done When

- `tests/generator_cases/rust_checked/expected/src/lib.rs` shows the
  no-declared-errors function returning its payload and the declared-errors
  function returning `Result`, and the golden compiles under the build's
  `rustc -D warnings` step.
- A program with a status channel and no declared errors emits no
  `src/error.rs` and its `lib.rs` names no `Error`.
- A unit test in `src/gen/generator.zig` covers the shape that used to produce
  an uncompilable crate, so the bug cannot come back silently.
- `zig build test --summary all` green; `scripts/update-generator-cases.sh`
  then `git status --short tests/generator_cases` empty apart from the new
  case; thirteen Go examples green with no drift; the Rust example's full list
  green; `zig fmt --check src build build.zig` clean. Committed.
