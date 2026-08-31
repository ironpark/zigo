---
depends_on:
- "48-48-abi-owns-c-names#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: No `structRecord(...).?` remains outside the nested-member sites.
> NEXT: none

# Functions carry their own struct records

## Planned Work

- Lower value structs before functions so a function can reference a lowered
  record.
- Add the record to `AbiParam` (for `.struct_in`/`.struct_out`) and to `AbiFn`
  for the returned or error-payload struct, keeping direct return and error
  payload distinguishable — the emitter branches on that difference at
  `emit.zig:828` and `865`.
- Replace `structRecord(...).?` at `emit.zig:792`, `810`, `817`, `871`, `880`
  with the carried record.
- Replace `returnsValueStruct` with the IR field; keep `structRecord` only for
  nested struct members.

## Done When

- No `structRecord(...).?` remains outside the nested-member sites.
- `returnsValueStruct` is gone.
- Artifacts still byte-identical; `zig build test` and `zig build check` pass.
