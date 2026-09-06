# GOALS

## Problem and the end result from the user's point of view

`.semantic = .codepoint` covers function parameters and returns only, checks only the Zig integer range, and has to be repeated at every site. Users want `rune` to appear wherever a codepoint travels (struct fields, callbacks), invalid runes to be rejected as such, and `u21` to be a codepoint by default when they ask for it.

## Measurable goals

- Every codepoint parameter (scalar or slice, `u21` or `u32`) rejects runes outside `0..0x10FFFF` with `*RangeError{Type: "codepoint"}`; functions with a `u32` codepoint parameter gain the `error` result this needs.
- `.codepoints = .infer_u21` on `zigo.define` marks every `u21` parameter/return (scalar or plain slice) as a codepoint unless the site says `.semantic = .integer`.
- `.field_meta.<name>.semantic = .codepoint` on a `.repr = .value` extern struct spells the mirror field `rune`; the struct stays castable.
- A registered callback type can declare `.param_semantics` and `.semantic = .codepoint`, and the public Go callback type spells `rune` while the stored raw closure keeps `uint32`.
- Misuse is `ZIGO053`; `abi-check` treats every hint change as breaking.

## Supported scope and non-goals

In scope: the four items above, generator cases, examples 02/04/09-or-11 as fits, docs and CHANGELOG. Non-goals: packed/materialized struct fields, callback slices, optional callback params, range checks inside struct fields or callback results (documented as reinterpretation).

## Reference source / commit / license

Plan 130 (`codepoint-semantic`), `writePackedCallbackAdapter` for the callback closure pattern.

## Completion criteria for the whole plan

`zig build test --summary all` green with new tests and goldens; touched examples pass `go vet`/`go test` on cgo and purego; docs updated.
