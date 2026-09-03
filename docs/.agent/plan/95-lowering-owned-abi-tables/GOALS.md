# GOALS

## Problem and the end result from the user's point of view

Several ABI facts are recomputed inside `src/gen/emit.zig` at every emit site instead of being decided once in lowering:

- Retained callback slot numbers: `retainedCallbackSlot`/`retainedCallbackSlotCount` (~line 8135) rescan `program.functions` at five emit sites; slot identity is an implicit "declaration order" convention.
- Flattened struct fields: `flattenedAbiParam` (~line 1021) linearly searches `function.params` and ends in `unreachable`.
- Packed struct bit layout is computed in the Go emitter (~line 4734) rather than carried by the lowered declaration.
- `variantOmitted` guards are repeated in about twelve loops across the emitter.
- `CIdentifierOrigin` in `src/gen/validate.zig` (~line 1082) carries `note` plus a `type_note: bool` at six call sites, allowing impossible combinations.

End result: lowering records these facts on the ABI IR (`src/gen/ir/abi.zig`) once, the emitter only reads them, and validation models the note origin as a tagged union. Generated output stays byte-identical; the golden cases are the safety net.

## Measurable goals

- `abi.AbiParam` gains `callback_slot: ?usize` (retained callbacks) and `flatten_index: ?usize` (or equivalent) set by lowering; `abi.AbiOpaque`/handle record gains `retained_callback_slots: usize`; the emitter no longer contains `retainedCallbackSlot*` scans or `flattenedAbiParam`.
- Lowered packed value structs carry per-field bit offsets and widths; the emitter renders from them.
- Omitted variants are dropped (or flagged once) during lowering so the emitter iterates only live variants; `variantOmitted` call sites in the emitter go to zero or one.
- `CIdentifierOrigin.note` becomes `union(enum) { none, function: []const u8, type: []const u8 }` (or similar) and the six call sites pass one value.
- No change to any file under `tests/generator_cases/*/expected` or any committed example `*_gen.go`, header, or shim. `abi-diff` results unchanged.
- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`, all 11 examples on cgo and purego green.

## Supported scope and non-goals

In scope: `src/gen/ir/abi.zig`, `src/gen/lower.zig`, `src/gen/emit.zig`, `src/gen/validate.zig`, `src/gen/abi_diff.zig` only if it serialises the new fields (prefer not to serialise them, or keep the JSON shape stable).
Non-goals: any behaviour or output change, new metadata, new diagnostics.

## Reference source / commit / license

Current main (`2bdc923`); plans 86 (callback slots), 87 (field accessors), 89 (value union payloads and omitted variants), 90 (flattened params), 93 (diagnostic notes).

## Completion criteria for the whole plan

Both phases done; verification loop green; `git diff --stat` after the work touches only `src/` (plus CHANGELOG if a `### Changed` internal note is wanted; optional); tree clean.
