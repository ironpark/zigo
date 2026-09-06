# SCOPE

`src/gen/ir/semantic.zig`, `src/gen/ir/abi.zig`, `src/gen/lower.zig`, `src/gen/validate/*.zig`, `src/gen/abi_diff.zig`, `src/gen/emit/{public,public_writers,public_types,public_runtime}.zig`, `src/reflect/walk.zig`, `tests/generator_cases/codepoint*`, examples, docs.

# CONTEXT

## Current implementation and bottlenecks

Range checks come from `abi.narrowInt`/`narrowSliceElement` and drive `lower.needsCheck`/`reportsPanics`. `TypeField` and `Callback` carry no semantic hints. The callback handle constructor converts the public func type to the raw one by a plain Go conversion, which only works while both spell the same types.

## Target structure and invariants

- `semantic.isCodepoint*` stay the only predicates; a codepoint position is range-checked against Unicode, never against the Zig width.
- Inference happens in reflection, so `semantic.json` always records explicit hints and the generator has no mode flag.
- Struct fields and callbacks convert by plain `rune(x)`/`uint32(x)` casts; no new runtime helpers.
