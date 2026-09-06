# GOALS

## Problem and the end result from the user's point of view

Zig text code passes Unicode codepoints as `u21` or `u32`, and the generated Go API spells them `uint32` / `[]uint32`. Go's idiomatic type is `rune`. A `.semantic = .codepoint` hint on a parameter or return makes the public Go signature use `rune` / `[]rune` while the raw layer keeps its `uint32` carrier.

## Measurable goals

- `.semantic = .codepoint` on a `u21`/`u32` parameter or return spells `rune` publicly; on a `[]const u21`/`[]const u32` (in or out) parameter or a slice return it spells `[]rune` with no copy on the public/raw boundary.
- `u21` range checks still fire (negative runes and values above 0x1FFFFF return `*RangeError`).
- Misplaced hints (any other type shape) are rejected with `ZIGO053`; `abi-check` reports hint changes as breaking.

## Supported scope and non-goals

In scope: plain `u21`/`u32` scalars and plain slices of them in parameters (in/out), returns, error-union payloads, optional scalar returns, purego and cgo backends. Non-goals: struct fields, callback parameters, `?u32` parameters, materialized results, injected/flatten parameters.

## Reference source / commit / license

Existing `utf8_string` hint plumbing (`semantic.isUtf8Slice`, `writePublicReturnType` hint argument, `renderRangeChecks`) in this repository.

## Completion criteria for the whole plan

`zig build test` passes with new reflection/validation/lowering tests and a `codepoint` generator case (cgo + purego); examples 02 and 11 expose `rune`; docs, diagnostics and CHANGELOG describe the hint.
