# GOALS

## Problem and the end result from the user's point of view

A struct that holds pointers cannot cross by value today, so it becomes an opaque handle plus one native call per field. Result size then scales call count: a provenance probe with ~130 field reads and 55 nested handles per result, over a 15,405 item corpus, costs roughly 0.4 s of pure boundary overhead on top of handle creation and cleanup, where the native side does the whole job in one `probe_many` call. End result: a struct registered with `.repr = .materialized` is returned (also inside slices, `![]Snapshot`) as one buffer: the generated Zig walker serializes the tree (offset table plus string blob) in one call, the generated Go decoder builds idiomatic Go structs with `string`, `[]T`, `*T` fields, and one release call frees the buffer. One cgo call plus one release per tree; batch loops can reuse a caller buffer through `.direction = .out` + `.written = .@"return"`.

## Measurable goals

- Registration: `.repr = .materialized` on a struct; the reflector walks the tree (scalars, bool, enums, strings, slices of scalars/strings/materialized structs, optional and non-optional pointers to materialized structs, nested materialized structs) and rejects cycles, opaque pointers inside the tree, callbacks and unions with a ZIGO diagnostic naming the field path.
- Layout: a versioned binary layout (header with layout version, node count, blob length; fixed-size node records; offsets relative to buffer start) documented in `docs/abi.md`; `abi-check` includes the layout version and the field list so a change in the tree is reported like any lowering change.
- Zig side: generated walker in the shim allocating with the registered allocator; `release` frees the buffer; ownership follows `.returns = .caller` + `.release`.
- Go side: generated decoder (cgo and purego) producing the public struct; zero-copy is not required, one copy from the buffer is fine; strings become Go strings.
- Positions: return value, error-union payload, slice element (`[]T` return with one buffer for the whole slice), `.direction = .out` parameter with `.written = .@"return"` for buffer reuse.
- Proof: new example `12-materialized` (or extension of 09) with a nested tree, a batch function returning `[]T`, Go tests on both backends including a benchmark comparing accessor handles to materialized decode; generator case pinning the shim, C header and Go decoder.
- Docs `bindings.md` repr table and a new section; `configuration.md` if any option is added; CHANGELOG `## [Unreleased]` `### Added`.

## Supported scope and non-goals

In scope: `src/reflect/walk.zig`, `src/gen/ir/semantic.zig`, `src/gen/lower.zig`, `src/gen/emit.zig` (shim, C header, cgo, purego), `src/gen/abi_diff.zig`, `src/gen/validate.zig`, examples, docs. Non-goals: materialized structs as inbound parameters (Go to Zig), cyclic graphs, zero-copy views, streaming decode.

## Reference source / commit / license

Current main; tagged-union `.access = .snapshot` (the existing "flatten one variant into an extern struct and read it once" precedent in `lower.zig`/`emit.zig`), plan 89 (value union payloads), plan 90 (flatten), plan 95/96 (lowering-owned ABI tables).

## Completion criteria for the whole plan

All phases done; verification loop green; tree clean; example benchmark shows one native call per tree.
