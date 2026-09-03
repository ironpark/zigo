# GOALS

## Problem and the end result from the user's point of view

A. `.name` on a function with `.constructs` is ignored: `emit.zig` renders every constructor as `New<Type>` (public wrapper naming, `constructorForInit`), so `.name = "extractAudio"` still produces `NewAudioBuffer`. End result: `.name` is honored for the Go wrapper of a constructor; if honoring it is impossible for a constructor kind, a diagnostic states that `.name` is ignored because `.constructs` decides the name.

B. Cancellation forces the error name `Canceled` (`validate.zig` ZIGO026) while the library uses `Cancelled`, forcing a translating wrapper. End result: `.cancel = .{ .param = "cancel", .canceled = "Cancelled" }` names the error; validation checks the named error; generated Go maps that error to `ctx.Err()` and `ErrCanceled`. The `*const std.atomic.Value(u32)` flag type stays as is.

## Measurable goals

- A: generator case with `.constructs` + `.name` proves the Go constructor uses the given name (PascalCase), lifecycle wiring (`constructorForType`, child constructors, Must variants if plan 103 landed) still finds it; abi-diff reports a Go signature change when the name changes; docs `bindings.md`.
- B: `.canceled` metadata recorded in semantic.json (`cancel_error`), default `Canceled`; ZIGO026 text names the configured error; generator case with `Cancelled`; example or unit test on the Go mapping; docs; CHANGELOG `## [Unreleased]` `### Added`/`### Fixed`.

## Supported scope and non-goals

In scope: `src/reflect/walk.zig`, `src/gen/ir/semantic.zig`, `src/gen/validate.zig`, `src/gen/emit.zig`, `src/gen/abi_diff.zig`, docs, cases. Non-goals: accepting `Value(bool)` cancel flags.

## Reference source / commit / license

Current main; `boxedConstructorName`, `constructorForInit`, ZIGO026 in `validate.zig`, `renderCancelSetup`.

## Completion criteria for the whole plan

Both phases done; verification loop green; tree clean.
