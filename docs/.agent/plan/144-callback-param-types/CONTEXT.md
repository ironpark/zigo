# SCOPE

`src/gen/emit/shim.zig`, `src/gen/emit/common.zig`, `src/gen/emit/callbacks.zig`, `src/gen/emit/type_spelling.zig`, `src/gen/validate/callbacks.zig`, `src/gen/validate/validate.zig`, `tests/generator_cases/callback_enum_handle*`, `docs/diagnostics.md`, `docs/cheatsheet.md`, `docs/bindings-callbacks.md`, `CHANGELOG.md`.

# CONTEXT

## Current implementation and bottlenecks

`semanticScalar` maps `.@"enum"` to its tag integer and `.opaque_ptr` to the bare `.@"opaque"` scalar; `shim.zig:49` and `callbacks.zig:357` spell the trampoline from it. `needsCallbackThunk` only inserts a thunk for packed, bool, moved userdata, and purego floats, so an enum reaches the native `*const fn` as `i32`. `typeOffense` treats every callback parameter node by the ordinary rules, so a slice passes.

## Target structure and invariants

The native-facing signature (thunk or extern trampoline) is spelled from the semantic node with `writeCallbackNativeType`; the Go-facing wire signature uses the promoted scalar. Enum crosses as its tag through `@intFromEnum`/`@enumFromInt` inside the thunk. A handle pointer crosses as a pointer on both sides. Validation admits only bool, integer, float, registered enum, packed value, and pointer-to-handle parameters, and bool, integer, float, enum, packed, void results.
