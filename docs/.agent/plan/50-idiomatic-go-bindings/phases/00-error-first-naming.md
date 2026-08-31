---
perf_phase: false
status: in-progress
---
> DONE-WHEN: No exported generated identifier panics without a `Must` prefix (verified by
> NEXT: none

# Error-first naming: base methods return errors, Must variants panic

## Planned Work

- In `src/gen/emit.zig`, invert the generated surface: emit `X() (T, error)`
  bodies where `TryX` bodies are emitted today, and emit `MustX` wrappers where
  the panicking `X` is emitted today. Drop the `Try` prefix entirely.
- Ordinary handle methods (e.g. `Push`, `SetMode`) stop panicking: methods
  that already return `error` fold the handle check into that error; methods
  that currently return a bare value gain an `error` result (or a `Must*`
  companion where the generator knows the call cannot fail natively).
- Update generated doc comments to describe the error return; keep
  `HandleError`/`NativePanicError` semantics unchanged.
- Update generator golden fixtures and example hand-written tests that call
  renamed methods.

## Done When

- No exported generated identifier panics without a `Must` prefix (verified by
  grepping regenerated example output for `panic(` outside `Must*` bodies and
  the helper that serves them).
- `zig build test` passes with updated goldens; regenerated examples 04, 05,
  and 10 compile and their Go tests pass.
