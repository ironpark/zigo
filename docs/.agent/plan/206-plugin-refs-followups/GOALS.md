# GOALS

## Problem and the end result from the user's point of view

Plan 205 left two gaps. Field- and tag-level `use` live in `src/declare.zig`, which cannot see the
authoring `TypeRef`/`FunctionRef`/`Interface` types, so a reference option on a struct field or enum
tag must be written as a raw path string while the same option on a function or type is written as
`api.typeRef(...)`. And `json`'s enum `UnmarshalJSON` walks `<Type>Values()` comparing `String()`
even when the generator already emits `Parse<Type>` (enums with `.text = true`). After this plan every
`use` site accepts the same authoring spellings, and json decodes through `Parse<Type>` whenever it
exists, keeping `IsKnown()` as the membership gate.

## Measurable goals

- A `plugin.ref.Type` field option written as `.{ .target = api.typeRef("X") }` on a value field and on an enum tag compiles, round-trips to `ext` as a native path, and resolves.
- For an enum with `.text = true` and both json and enumkit attached, generated `UnmarshalJSON` calls `Parse<Type>` and `IsKnown()`, and contains no `Values()` loop.
- Contract stays 7.0 unless a public type moves; generated output byte-identical for bindings not using these features.

## Supported scope and non-goals

In scope: `src/author.zig`, `src/declare.zig`, `src/normalize.zig`, `plugins/json`, goldens, docs. Out of scope: a plugin distribution or test kit.

## Reference source / commit / license

Baseline: tag 0.29.0 (commit 29f94580). MIT.

## Completion criteria for the whole plan

Both phases done; docs updated; CHANGELOG `Unreleased` records both changes.
