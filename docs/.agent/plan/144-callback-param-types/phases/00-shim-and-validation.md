---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zig build test` passes; the new cases' shims compile with `zig build-obj` against a stub target module; the `/tmp/zigo-repro` documents no longer crash.
> NEXT: none

# Shim spelling and validation

## Planned Work

- Spell `opaque_ptr` callback parameters as pointers in the cgo extern trampoline, the cgo `//export` Go signature, and the thunk native signature.
- Spell enum parameters and results as the target enum type in the thunk native signature, forwarding through `@intFromEnum` and `@enumFromInt`; extend `needsCallbackThunk` to enum.
- Add a ZIGO057 rule in `validate/callbacks.zig` refusing other callback parameter and result shapes, with unit tests.
- Add generator cases `callback_enum_handle` (cgo) and `callback_enum_handle_purego` and compile their shims against a target module.
- Document ZIGO057 and the callback value-type table; add changelog entries.

## Done When

- `zig build test` passes; the new cases' shims compile with `zig build-obj` against a stub target module; the `/tmp/zigo-repro` documents no longer crash.
