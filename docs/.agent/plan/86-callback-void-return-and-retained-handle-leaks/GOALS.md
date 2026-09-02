# GOALS

## Problem and the end result from the user's point of view

Two callback defects reported from gostty (libghostty-vt bindings):

A. Registering `*const fn (userdata: usize) callconv(.c) void` with `.repr = .callback` on the cgo backend panics inside the generator (`semanticScalar` `else => unreachable`, reached from `renderShim`) instead of producing a diagnostic or working. The purego validator (ZIGO014) already documents `void` as an allowed callback result, so the backends disagree.

B. A method that takes a `.retention = .retained` callback on an existing handle (for example `Stream.onClipboardWriteRequest`) creates a new `cgo.Handle` per call but never deletes it on the success path, and neither `Close` nor the cleanup net deletes it. Only constructors that retain callbacks get `callbackHandles` on the handle (`typeOwnsCallbacks` only inspects constructor/owned-return functions). Re-registering leaks the previous handle, its `CallbackState`, and the Go closure for the process lifetime.

End result: a `void` callback return works on both backends (a `void` result is emitted end to end; no unreachable), and every retained callback registered through a method is owned by the receiver handle: re-registering the same parameter slot releases the previous handle after the native call succeeds, and `Close`/cleanup release every retained handle. `ActiveCallbackHandleCount` returns to zero after Close.

## Measurable goals

- Registering a `void`-returning callback on cgo and purego generates, compiles, and runs; a unit test plus a generator case cover it. If full support turns out to need ABI changes beyond a `.void` result branch, a `ZIGO0NN` diagnostic (next free code after ZIGO036) is the fallback, but support is the goal since ZIGO014 already promises `void`.
- A Go test registers a retained callback twice on one handle then closes it, and asserts the active callback handle count returns to its starting value on both backends.
- `zig build test --summary all` and `zig fmt --check build.zig src tests examples` clean; all 11 examples pass cgo and purego checks, Go vet/test, example 07 `-race`.

## Supported scope and non-goals

In scope: `src/reflect/walk.zig` (if the void return is dropped or mistyped there), `src/gen/validate.zig`, `src/gen/emit.zig` shim/runtime/handle emitters for cgo and purego, generator case snapshots, an example that exercises a retained callback method (extend an existing callback example rather than adding a new one), docs (`docs/` callback section), CHANGELOG `## [Unreleased]`.
Non-goals: version bump, tags, pushes, changing the borrowed-callback path, changing the panic-rethrow design.

## Reference source / commit / license

Current main (0.6.2, `60905a9`). Related prior work: plan 82 (dependent handles), 84/85 (borrowed views and lifecycle counters), purego callback registry in `renderPuregoRuntime` (`callbackRegistry`, `DeleteCallbackHandle` drain).

## Completion criteria for the whole plan

All phases done, the tree clean, tests/format/examples green as listed above, CHANGELOG updated under `## [Unreleased]` with `### Added`/`### Fixed` entries describing A and B, no leftover draft files at the repo root.
