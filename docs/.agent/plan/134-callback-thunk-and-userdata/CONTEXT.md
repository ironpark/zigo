# SCOPE

`src/reflect/walk.zig`, `src/gen/ir/semantic.zig`, `src/gen/lower.zig`, `src/gen/emit/{common,shim,callbacks,type_spelling}.zig`, `src/gen/validate/{validate,callbacks}.zig`, `src/gen/abi_diff.zig`, `tests/generator_cases`, `docs/bindings-callbacks.md`, `docs/cheatsheet.md`, `docs/diagnostics.md`.

# CONTEXT

## Current implementation and bottlenecks

`type_spelling.semanticScalar` maps `bool` to `bool_u8`, spelled `u8` in Zig; the cgo trampoline extern and packed thunk use it verbatim, so the function pointer type disagrees with the Zig target. `common.needsCallbackBitThunk` returns false on cgo. `semantic.Callback.has_userdata` is a bool derived in `walk.zig` from "last param is usize"; `lower.pairUserdataParams` pairs the token with the parameter after the callback; `callbacks.zig` hard-codes `userdata_index = len - 1` and bails with `error.CallbackRequiresUserdata`.

## Target structure and invariants

Go dispatchers and trampolines keep a single convention: values first, userdata last, scalars promoted. Every difference between the native callback signature and that convention (floats, packed, bool, userdata position) is absorbed by one shim thunk per callback parameter. Reflection defaults `userdata_index` to the last `usize`; the callback type entry may override it; validate refuses signatures whose declared userdata slot is not `usize` or whose owning function has no `usize` token parameter.
