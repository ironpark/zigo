# SCOPE

`src/gen/ir/semantic.zig`, `src/reflect/walk.zig`, `src/gen/lower.zig`, `src/gen/validate/callbacks.zig`, `src/gen/emit/{shim,callbacks,public_writers,public_types,common,purego}.zig`, generator cases, `examples/04-callback`, `examples/10-tagged-union`, docs, CHANGELOG.

# CONTEXT

## Current implementation and bottlenecks

Every callback parameter lowers to exactly one `AbiScalar`, and every emitter that walks a callback signature assumes one native slot per Go parameter. Value unions decode payloads into unexported fields.

## Target structure and invariants

A `.slice` node of const `u8` in `Callback.params` means a `[*]const u8` + `usize` pair (two native slots) unless it is sentinel-terminated (one `[*:0]const u8` slot). `semantic.Callback` owns the slot arithmetic so shim, exports and dispatchers share one mapping. Go receives a copy.
