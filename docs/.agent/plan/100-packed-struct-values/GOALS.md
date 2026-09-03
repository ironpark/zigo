# GOALS

## Problem and the end result from the user's point of view

A `packed struct(u16)` of bool and enum fields (ghostty's `Style.Flags`, gostty's `RenderCell.Flags`) crosses today only as a value-union payload (plan 89 emits a Go mirror with `zigo<Name>ToBacking`/`FromBacking` for that case). Registered on its own with `.repr = .value` it is rejected with ZIGO003, so consumers receive a bare `uint16` and re-derive the bit layout by hand (`flagBold = 1 << iota`, `(cell.Flags >> 8) & 0xf`), which silently drifts when upstream repacks. End result: `.repr = .value` accepts an integer-backed `packed struct` whose fields are bool, integers, or registered enums (and nested such packed structs); Go gets the mirror struct plus `Backing()` / `<Name>FromBacking(v)` conversions; the type crosses C as its backing integer wherever a scalar can: whole parameters, returns, error payloads, optionals, `extern struct` fields, `.fields` accessors, `.flatten` fields, value-union payloads (already), callback parameters.

## Measurable goals

- `.repr = .value` on such a packed struct produces a Go mirror in the public package with typed fields, `Backing()` and `<Name>FromBacking()`; unsupported fields (floats, pointers, non-registered enums, plain structs) get a diagnostic (next free ZIGO code, check the highest in use) naming the field.
- Whole parameter and return use the backing integer on the C side and the mirror on the Go side on both backends; extern struct fields of packed type are emitted as the mirror in the Go struct with conversion in both directions; `.fields` and `.flatten` accept a packed leaf.
- abi-diff: field append inside a packed struct that keeps the backing width is compatible; reorder, width change, or removal is breaking.
- Generator case, example (extend 10 where `RGB` is `packed struct(u24)`, or 09 which registers `Point`), docs `bindings.md` "Extern struct 값" gains a packed subsection, `limitations.md`, CHANGELOG `## [Unreleased]` `### Added`.

## Supported scope and non-goals

In scope: `walk.zig` registration path, `validate.zig` ZIGO003 carve-out, `lower.zig` (reuse `AbiPacked` from plan 95), `emit.zig` mirror emission reuse, docs, tests.
Non-goals: packed structs without an integer backing, packed structs wider than 64 bits, exporting individual bit constants (the mirror replaces them).

## Reference source / commit / license

Current main; plan 89 packed payloads; plan 95 `AbiPacked`/`Program.packedLayout`.

## Completion criteria for the whole plan

Phase done; verification loop green; tree clean.
