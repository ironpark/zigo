---
depends_on:
- "131-codepoint-reach#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: `value_adapter`-style case shows a `rune` field crossing both ways; tests green.
> NEXT: none

# Extern struct fields

## Planned Work

- `TypeField.semantic`, `AbiStruct.Field.semantic`, `.field_meta` on `.repr = .value` entries, ZIGO053 for non-`u32` or non-extern fields, abi_diff field hint comparison.
- Mirror field spelled `rune`; `zigo{T}ToRaw/FromRaw` cast; castability unchanged; generator case coverage.

## Done When

- `value_adapter`-style case shows a `rune` field crossing both ways; tests green.
