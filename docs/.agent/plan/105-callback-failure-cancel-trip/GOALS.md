# GOALS

## Problem and the end result from the user's point of view

Callback failure sentinels are in-band: a Go callback that panics returns `-3`, a deleted token returns `-4` (`writeCallbackFailureValue`, cgo dispatcher `result = C.int32_t(-3)` in `src/gen/emit.zig`). Native code that treats "non-zero means continue" keeps running after a panic and the panic is only rethrown after the call ends. This is documented but cannot be fixed by documentation. End result:

1. When the function owning the callback has a `.cancel` parameter, a callback failure (panic, deleted token, Go error) sets that cancel flag before returning, so the native loop stops at its next poll even if it ignores the sentinel.
2. A binding may declare `.on_callback_failure = .{ .result = <value> }` on the callback type entry (or the function's callback parameter) so the dispatcher returns the domain's own stop value instead of `-3`/`-4`; the failure is still recorded and rethrown after the call.

## Measurable goals

- Cancel trip: no callback ABI change; the callback state carries the cancel flag pointer for the duration of the call; both backends (cgo, purego) and both dispatcher styles set it with a sequentially consistent store. Go test in example 04 (or a new cancellable-with-callback function in 07): a panicking progress callback stops a long native loop that ignores the return value.
- Fallback result: `on_callback_failure` recorded in semantic.json and abi-diff treats it as a compatible change; validation error (new ZIGO code) when the value does not fit the callback's return type or the callback returns void; generator case covering an i32 callback with `.result = 0`.
- Docs `bindings.md` callback failure section rewritten; CHANGELOG `## [Unreleased]` `### Added`.

## Supported scope and non-goals

In scope: `src/reflect/walk.zig` metadata, `src/gen/ir/semantic.zig`, `src/gen/validate.zig`, `src/gen/emit.zig` dispatchers (cgo and purego), example tests, docs. Non-goals: changing the sentinel values themselves; out-of-band failure channels that change the callback ABI.

## Reference source / commit / license

Current main; `writeCallbackFailureValue`, `renderCancelSetup`, plan 86 (void callbacks and retained handles), plan 93 (callback contract diagnostics).

## Completion criteria for the whole plan

Both phases done; verification loop green; tree clean.
