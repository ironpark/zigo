---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Both cases generate, `zig build test` passes, and the shim for the cgo case compiles under `zig build` in a scratch example.
> NEXT: none

# Bool callbacks through the shim thunk

## Planned Work

- Generalize `needsCallbackBitThunk` into `needsCallbackThunk` covering both backends and bool params/results.
- Thunk: `@intFromBool` on bool params, `!= 0` on a bool result; cgo trampoline extern stays `u8`.
- Relax `ZIGO014` to accept a `bool` result on purego.
- Add `callback_bool` and `callback_bool_purego` generator cases and a reflect/lower unit test.

## Done When

- Both cases generate, `zig build test` passes, and the shim for the cgo case compiles under `zig build` in a scratch example.
