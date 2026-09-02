# GOALS

## Problem and the end result from the user's point of view

By-value tagged union parameters (plan 81) accept only void/bool/scalar/enum payloads, so a union like ghostty's `sgr.Attribute` (payloads `color.RGB` packed struct, `Underline` enum, `Unknown` struct with a slice) forces downstream projects to keep a hand-written 30-variant mirror that silently drifts from upstream. The end result: value unions accept payloads that are `extern struct`/`packed struct` of scalars (recursively), registered `.repr = .value` structs, and a per-registration `.omit_variants` list for the few variants that cannot cross (documented as absent on the Go side). Value unions can also be returned by value.

## Measurable goals

- Payload kinds accepted in value unions: existing scalars/enums, `packed struct` with integer backing (crosses as its backing integer), `extern struct` whose fields are all scalars/enums/nested such structs (crosses as the flattened field slots, or as a registered `.value` struct when one exists).
- `.omit_variants = .{ "unknown" }` on the union registration removes those variants from the C/Go surface; using an omitted tag at runtime in a return position reports an error status (`ZIGO`-style typed Go error) rather than UB.
- Value unions as return types (`fn current() Attribute`) through an out-parameter snapshot in the shim, on both backends.
- A remaining unsupported payload still produces ZIGO006 naming the variant, now with a hint mentioning `.omit_variants`.
- Generator case, example update (extend example 10 or the one that carries `ScrollViewport`), docs, CHANGELOG, `abi-diff` rules (variant append remains breaking for value unions).

## Supported scope and non-goals

In scope: `walk.zig` union reflection, `validate.zig` ZIGO006 paths, `lower.zig` value-union slot layout, `emit.zig` constructors/accessors, docs `bindings.md` "Tagged union projection" value section.
Non-goals: slice or pointer payloads in value unions, unions nested inside other value unions beyond one level of struct, changing the pointer-handle projection.

## Reference source / commit / license

Current main; plan 81 (tagged-union-value-params) for the slot layout; `docs/bindings.md` value-union paragraph.

## Completion criteria for the whole plan

All phases done; full verification loop green; docs and CHANGELOG updated; tree clean.
