# GOALS

## Problem and the end result from the user's point of view

`std.atomic.Value(T)` is `extern struct { raw: T }` in std, so it is C-representable, but zigo only recognises the cancel flag `*const std.atomic.Value(u32)` (`src/reflect/walk.zig` `isCancelFlag`). Anywhere else it reflects as an unregistered extern struct named `Value(u64)` and is rejected by `.fields`, `.flatten`, value structs, and union payloads. Upstream libraries keep atomic counters and flags inside handle state (ghostty's `kitty/graphics_storage.zig` has `std.atomic.Value(u64)`), and downstream bindings want to read them from Go while native code runs.

End result:

1. In every value position where a scalar is allowed, `std.atomic.Value(T)` with T bool, integer, float, or registered enum behaves as `T`: `.fields` getters/setters (`load(.seq_cst)` / `store(v, .seq_cst)`), `.repr = .value` extern struct fields, `.flatten` fields, value-union payloads, by-value parameters and returns (`.raw` / `.init(v)`). The Go surface is plain `T`; semantic.json and the C ABI gain no new concept.
2. `*std.atomic.Value(T)` and `*const std.atomic.Value(T)` parameters with T in `u32, i32, u64, i64` are accepted as call-scoped (borrowed) shared flags, exposed in Go as `*atomic.Uint32`, `*atomic.Int32`, `*atomic.Uint64`, `*atomic.Int64` from `sync/atomic`, generalising the cancel flag's memory handling. Other T (bool, u8, u16, floats) are rejected with a diagnostic because Go cannot store them atomically; retained atomics are rejected because native must not keep a Go address.

## Measurable goals

- Phase 0: a unit test in `walk.zig` reflects a handle with `counter: std.atomic.Value(u64)` and `enabled: std.atomic.Value(bool)` through `.fields` (getter and setter), a `.flatten` field of atomic type, an extern struct with an atomic field registered `.repr = .value`, and a value union with an atomic payload; semantic.json for each shows plain scalars; generated shim uses `load`/`store`/`.raw`/`.init`; an extern struct with an atomic field takes the copy path, never the cast path; a generator case pins the shim; an example (extend 03 or 04) reads and writes an atomic field from Go on cgo and purego.
- Phase 1: `*std.atomic.Value(u64)` and `*const std.atomic.Value(i32)` parameters bind as `*atomic.Uint64` / `*atomic.Int32`; the shim receives a pointer to the Go-side value for the duration of the call (same mechanism the cancel flag uses; check how `cancel` allocates and pins the flag on cgo and purego and reuse it); a diagnostic (next free ZIGO code) rejects unsupported widths and `.retention = .retained`; the cancel flag path keeps its dedicated `ctx` semantics and snapshots unchanged; example test on both backends where native increments a counter the Go side then reads.
- No existing golden or example generated file changes; full verification loop green; docs (`bindings.md` new subsection, `limitations.md`) and CHANGELOG `## [Unreleased]` `### Added`.

## Supported scope and non-goals

In scope: `walk.zig` (detect `std.atomic.Value(T)` by comparing `T == std.atomic.Value(fields[0].type)` before the struct branch of `typeNode`, plus `.fields`/flatten leaf checks), semantic IR only if a marker is needed for the shim (prefer recording nothing new in semantic.json for phase 0: the shim reads the Zig type from the reflected path; if the shim cannot know a field is atomic without a marker, add an `atomic: bool` on `FlattenedField`/`TypeField`/field-access origin and document it), `emit.zig` field access and struct conversion, `validate.zig`, docs, examples, generator cases.
Non-goals: `*std.atomic.Value(T)` returns, exposing memory orders, RMW operations (`fetchAdd`, `cmpxchg`), atomics inside slices' cast path (they take the copy path).

## Reference source / commit / license

Current main; cancel flag: `docs/bindings.md` "취소 (`.cancel`)" and `walk.zig` `isCancelFlag`; field accessors plan 87; flatten plan 90; value unions plan 89.

## Completion criteria for the whole plan

Both phases done; verification loop green; tree clean.
