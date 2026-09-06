# SCOPE

- `src/gen/ir/abi.zig`, `src/gen/lower/materialized.zig`,
  `src/gen/validate/materialized.zig`, `src/reflect/walk.zig`,
  `src/gen/emit/materialized_encoder.zig`, `materialized_decoder.zig`,
  `raw.zig`, `purego.zig`, `public.zig`, `public_writers.zig`.
- `src/reflect/coverage.zig` for enum `.covers`.
- `tests/generator_cases/materialized*`, `examples/12-materialized`.
- `docs/abi.md`, `bindings-types.md`, `limitations.md`,
  `configuration.md`, `cheatsheet.md`, CHANGELOG.

# CONTEXT

## Current implementation and bottlenecks

Layout 1 gives every field a 16-byte slot and every scalar slice element 8
bytes; `Field.Kind` is a flat enum, so nesting is limited to what it names.
Raw Go copies the buffer, releases it, and returns the copy.

## Target structure and invariants

- `MaterializedLayout.Shape`: `scalar{width}`, `string{bytes, nullable}`,
  `optional{child}` (presence byte, child at its own alignment),
  `sequence{element}` (offset+count, elements at the element stride),
  `node{ref, pointer, nullable}` (8-byte offset, 0 = null), and
  `value_struct{fields}` (inline record). Records and arrays are 8-aligned.
- Magic word `0x0002_4f47495a`; header unchanged.
- Raw Go hands the public layer an `unsafe.Slice` view plus the release;
  decoding copies everything it keeps, then releases.
