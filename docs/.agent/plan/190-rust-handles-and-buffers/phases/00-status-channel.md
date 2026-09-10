---
completed_at: "2026-09-10T05:49:18Z"
perf_phase: false
status: done
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

  **Outcome: the audit was run empirically, and it found two more bugs than
  the plan expected.** Rather than reason about the refusal list, every one of
  the 74 Go generator cases' `semantic.json` was fed to the Rust target and
  each accepted result compiled with `rustc -D warnings`. Before this phase 8
  documents were accepted; after it 4 are, and all 4 compile.

  `lower.reportsPanics` has exactly three triggers -- a handle receiver, a
  handle parameter, and a narrow-integer parameter -- and only the third was
  reachable, which is the bug this phase fixes. But the same audit found two
  *silent degradations* that had nothing to do with the status channel and
  everything to do with the same failure mode, a crate that compiles while
  quietly discarding what the binding said:

  - **A registered enum arrived as its bare tag integer.**
    `type_spelling.semanticScalar` maps an enum to its tag, so
    `echo(value: EraseDisplay) EraseDisplay` was generating
    `pub fn echo(value: u8) -> u8`. Correct at the ABI and useless to a
    caller, who has no way to learn that `0` means `below`. Go emits a named
    type with constants.
  - **A namespaced free function lost its namespace.**
    `unicode.codepointWidth`, `unicode.grapheme.breaks` and
    `osc.parser.state.parse` all became flat `pub fn` items, so two
    same-named functions in different namespaces would have collided into one
    definition.
  - **Sub-packages were merged into one crate root**, for the same reason.

  All three are now refused with `ZIGO060`. Mapping an enum to a
  `#[repr(u8)]` Rust enum and a namespace to a Rust module are both real
  features that deserve their own plan; refusing is a few lines and turns a
  wrong answer that compiles into a named refusal, which is what the plan's
  own invariant demands. Recorded as hand-off items in phase 5.

  The namespace refusal is deliberately narrow -- `receiver == null and
  namespace != null` -- because a *method* also carries a namespace, its
  receiver type, and phase 2 needs those to be judged by the receiver rules
  instead.

- Also fixed, found while rewriting the result shape: `Payload.scalar`
  carried only the *raw* spelling, so `error{E}!bool` arrived as
  `Result<u8, Error>`. It now carries both spellings, like `Direct` already
  did, and `rust_checked` pins the `bool` case.
- Also fixed: `src/gen/targets/rust.zig` failed `zig fmt --check` at the
  branch point (a trailing blank line left by plan 189), which blocked this
  plan's own verification gate. One line, unrelated to the rest of the phase.

## Done When

- `tests/generator_cases/rust_checked/expected/src/lib.rs` shows the
  no-declared-errors function returning its payload and the declared-errors
  function returning `Result`, and the golden compiles under the build's
  `rustc -D warnings` step.
- A program with a status channel and no declared errors emits no
  `src/error.rs` and its `lib.rs` names no `Error`.
- A unit test in `src/gen/generator.zig` covers the shape that used to produce
  an uncompilable crate, so the bug cannot come back silently, and a second
  covers the three silent degradations the audit found.
- Re-running the audit accepts only scalar-only documents, and every one of
  them compiles under `rustc -D warnings`.
- `zig build test --summary all` green; `scripts/update-generator-cases.sh`
  then `git status --short tests/generator_cases` empty apart from the new
  case; thirteen Go examples green with no drift; the Rust example's full list
  green; `zig fmt --check src build build.zig` clean. Committed.
