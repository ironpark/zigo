# SCOPE

`src/gen/ir/semantic.zig`, `src/gen/validate/functions.zig`, `src/gen/abi_diff.zig`, `src/gen/emit/public_writers.zig`, `src/gen/emit/public.zig`, `src/reflect/walk.zig` tests, `tests/generator_cases/codepoint*`, `examples/02-errors`, `examples/11-io-streams`, `docs/bindings-functions.md`, `docs/bindings-types.md`, `docs/diagnostics.md`, `CHANGELOG.md`.

# CONTEXT

## Current implementation and bottlenecks

`SemanticHint` has `c_string`, `opaque_bytes`, `utf8_string`. Hints live on `Parameter.semantic` and `SemanticFn.return_semantic`; reflection copies them from `param_meta` and function metadata. Narrow ints are promoted to their C carrier by `abi.narrowInt` and range-checked in `public_writers.renderRangeChecks`. Public spelling of ints goes through `writePublicGoType`, which has no hint, while `writePublicParameterType` and `writePublicReturnType` do see the hint.

## Target structure and invariants

- `semantic.isCodepoint(node, hint)` and `semantic.isCodepointSlice(node, hint)` are the only two predicates; every emitter asks them.
- Raw layer is untouched: `uint32` stays the carrier, so ABI, header, shim and purego output do not change.
- Public layer converts scalars with `uint32(x)` / `rune(x)` and slices with an `unsafe.Slice` reinterpretation helper `zigoRunesToUint32` / `zigoUint32ToRunes`.
