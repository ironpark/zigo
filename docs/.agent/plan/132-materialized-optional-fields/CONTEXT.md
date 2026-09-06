# SCOPE

- `src/gen/validate/materialized.zig`, `src/gen/lower/materialized.zig`,
  `src/gen/ir/abi.zig`, `src/gen/emit/materialized_encoder.zig`,
  `src/gen/emit/materialized_decoder.zig`.
- `tests/generator_cases/materialized`, `examples/12-materialized`.
- `docs/abi.md`, `docs/bindings-types.md`, `docs/limitations.md`,
  `docs/bindings-buffers.md`, `CHANGELOG.md`.

# CONTEXT

## Current implementation and bottlenecks

Every field owns a 16-byte slot. A scalar uses the first 8 bytes; a string
uses offset and length. The buffer header is 40 bytes, so a data offset of
0 never occurs and already means null for node pointers.

## Target structure and invariants

- `Kind.optional_scalar`: presence in the first u64, value in the second.
- `Kind.optional_string`: same offset/length pair; offset 0 means absent.
  An empty present string keeps a non-zero offset because bytes are
  appended after the header.
- Go types `*T` and `*string`. `abi-check` already treats `T` vs `?T` as
  breaking through the node tag comparison.
