# SCOPE

- A: `semanticScalar` must not be reached with `.void` for a callback result, or must handle it. Trace `renderShim` for the callback trampoline result path and emit `void` C/Zig/Go signatures (`func(...)` with no result in Go, `void` in C, `void` in the Zig shim, purego dispatcher returning 0 / ignoring). Validate that a `void` result is rejected only where the design truly needs a value (for example a callback that maps a Go `error`, already ZIGO-checked at `callbackGoErrorIssue`).
- B: extend ownership. `typeOwnsCallbacks` (and the `callbackHandles` field, constructor wiring, `cleanup`, `Close`) must also consider methods whose receiver is the type and that take a retained callback. For method registration: after the native call succeeds, store the new handle in the receiver's per-slot map keyed by function+parameter (under the handle's `mu`), and delete the previously stored handle for that slot. On failure keep the existing behaviour (delete the new handle). `Close`/cleanup delete every slot. Slots are per parameter, so a function registering two retained callbacks has two slots. Consider in-flight invocations: native has already swapped the pointer when the call returns, so the old handle sees no new calls; the purego registry drains active invocations, and on cgo document that `deleteCallbackHandle` after the native return follows the same rule the constructor path already relies on.
- Shared-lifecycle (`.packages`) variants of the runtime must get the same change.

# CONTEXT

## Current implementation and bottlenecks

- `src/gen/emit.zig` `renderCallbackHandleSetup` creates handles; borrowed ones are `defer`-deleted, retained ones only deleted on the error path by `writeDeleteRetainedCallbacks`. `writeRetainedCallbackHandles` passes retained handles into the constructor's `new<Type>` wrapper, which is the only place they get stored (`callbackHandles` slice) and later released in `cleanup<Type>` and Close.
- `typeOwnsCallbacks` at `emit.zig:7518` only checks functions that construct/return the type.
- `semanticScalar` at `emit.zig:~7010` has `else => unreachable`; the callback result of `.void` reaches it from `renderShim` (`emit.zig:292`).
- `validate.zig` `puregoCallbackIssue` (ZIGO014) allows `void` and `i32`; there is no cgo-side check.

## Target structure and invariants

- A callback result is `void` or a scalar; both backends emit the same trampoline shape for `void`.
- Every retained callback handle is reachable from exactly one owning Go handle until Close/cleanup, whichever comes first, and is deleted exactly once.
- `activeCallbackHandleCount()` (and the shared-lifecycle exported variant) is zero after all handles are closed in tests.
