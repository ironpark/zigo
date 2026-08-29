---
depends_on:
- "01-zigo-go-bindings#0"
perf_phase: false
status: planned
---
> DONE-WHEN: Serializing a fixture, parsing it back and re-serializing yields byte-identical output.
> NEXT: none

# Semantic IR types and error lock

## Planned Work

- Encode the `docs/02-ir-spec.md` schema as Zig types in `src/gen/ir/semantic.zig`:
  the type node union, function, parameter, type declaration, and constructor records.
- Implement deterministic serialization with sorted keys, so that committed
  `semantic.json` diffs carry no ordering noise, and matching deserialization.
- Implement `src/gen/ir/errors_lock.zig`: load, assign the next code to unseen error
  names, refuse any change to an existing mapping, never reuse a retired code, and
  reserve 0 and the negative range.
- Define `src/gen/ir/abi.zig` — `AbiFn`, `AbiParam`, `AbiScalar` — with a back-reference
  to the originating semantic function for the public Go layer.
- Round-trip tests over hand-written IR fixtures.

## Done When

- Serializing a fixture, parsing it back and re-serializing yields byte-identical output.
- Introducing a new error name appends a code while leaving existing codes untouched;
  editing an existing mapping is rejected with a diagnostic.
- `zig build test` covers the round-trip and error-lock cases.
