# GOALS

## Problem and the end result from the user's point of view

Every handle method returns `error` because of the lifecycle check, so `if cols, err := term.Cols(); err != nil` repeats endlessly in tests and scripts. Tagged-union projections already have `MustTag()`/`MustAs*()`. End result: an opt-in binding option (`.go_must_variants = true` in `addGoBindings`, default false so existing surfaces do not double) emits `Must<Name>` for every public function and method whose only error is the generated lifecycle/native error or a Zig error set, returning the value(s) without the error and panicking with the same typed error the `Must*` union accessors use.

## Measurable goals

- Option plumbed through the build helper, CLI, and generator; default off keeps every golden and example unchanged.
- `Must*` generated for functions returning `(T, error)`, `error` only (becomes no return), and multi-value returns; constructors get `MustNew<Type>`; `Close` is excluded; names go through the ZIGO024 collision check.
- Panics use the existing `zigoMust` helper and typed errors; Go doc comment states it panics.
- Generator case with the option on, one example opts in with a test asserting the panic value, docs `configuration.md` option row and `generated-code.md`, CHANGELOG `### Added`.

## Supported scope and non-goals

In scope: `build.zig` option, `src/gen/cli.zig`, `generator.zig`, `emit.zig` public rendering, docs.
Non-goals: per-function opt-in; changing existing error-returning signatures.

## Reference source / commit / license

Current main; `zigoMust`/`zigoMustMatch` helpers in the tagged-union emitter.

## Completion criteria for the whole plan

Phase done; verification loop green; tree clean.
