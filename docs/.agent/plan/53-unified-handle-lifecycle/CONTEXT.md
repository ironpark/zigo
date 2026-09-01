# SCOPE

Files expected to change: `src/gen/emit.zig` (unified handle template at and
around emit.zig:2588 and the AddCleanup emission path, method lock/KeepAlive
prologues, cleanup function emission), golden fixtures under `tests/`,
regenerated `examples/*/go*` trees, and new hand-written lifecycle tests in a
callback example and a non-callback example. Generated struct layouts change
(fields added), but no exported name or signature changes.

# CONTEXT

## Current implementation and bottlenecks

- `emit.zig:2588` emits the callback-program handle struct (`ptr`, `once`,
  `mu sync.RWMutex`, `callbackHandles`); a separate path emits the
  non-callback struct (`ptr`, `once`, `cleanup runtime.Cleanup`) plus
  `new<Type>`/`cleanup<Type>` helpers and `AddCleanup` registration.
- The choice is program-wide: example 04 gives mutexes to `FloatBuffer` and
  `IntBuffer`, which own no callbacks; example 10 gives no mutex to any type.
- Method prologues differ per scheme: RLock/RUnlock vs `defer
  runtime.KeepAlive(receiver)`.
- The callback registry (emit.zig:1175-1176) is a global map guarded by
  `callbackRegistryMu`, with entries tracking in-flight invocations
  (`active`, `closing`, cond var); `deleteCallbackHandle` already handles
  graceful teardown, so GC cleanup can call it.

## Target structure and invariants

- Single owned-handle template: fields `ptr`, `once`, `mu sync.RWMutex`,
  `cleanup runtime.Cleanup`, and — only when the type owns callbacks —
  `callbackHandles []zigoCallbackHandle`.
- Construction always registers `AddCleanup`. The cleanup state must carry
  the pointer and the callback-handle slice by value (the cleanup function
  must not retain the handle object itself, or it never runs).
- Close: `once.Do` → write-lock → `cleanup.Stop()` → deinit → release
  callback handles → nil fields. Cleanup (GC path): same release logic on
  the captured state; no locking needed since the object is unreachable.
- Methods: read-lock prologue; the deferred RUnlock keeps the receiver
  reachable for the duration of the native call, but keep the existing
  `runtime.KeepAlive` where the emitter relies on it today rather than
  reasoning it away — removing KeepAlive is out of scope.
- Ref types stay as they are (no locking; validity checks via parent).
- Emission stays deterministic and per-type; cgo and purego in lockstep.
