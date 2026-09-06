# GOALS

## Problem and the end result from the user's point of view

Materialized trees cannot hold `[N]T` arrays, `[][]T` nested slices, extern
struct values, binary `[]u8`, or an inline optional node, and every scalar
costs 8 bytes even when it is an `i16`. The Go side copies the whole native
buffer with `C.GoBytes` before decoding it again field by field, and `Fill`
decodes into a temporary slice before copying into the caller's. Separately,
an enum registered with `.repr = .enumeration` cannot declare `.covers`, so
its Zig methods stay `unbound` in `go-coverage` even when the Go enum stands
in for them.

After this plan, layout version 2 stores scalars at their natural width with
a recursive shape model that admits the missing field forms; Go decodes
straight from the native buffer and into the caller's slice; and enum type
entries accept `.covers`.

## Measurable goals

- `materialized` case and example 12 round-trip with arrays, nested slices,
  extern struct, `[]byte` and optional node fields on both backends.
- Example 12's decoded record shrinks and `BenchmarkMaterializedDecode`
  does not regress.
- `zig build test` passes; `go-coverage` shows an enum's covered methods as
  `wrapped`.

## Supported scope and non-goals

Version 2 replaces version 1: no dual-version decoding. `[]?T` and `?[]T`
(other than bytes) stay rejected. Packed structs are carried as their
backing integer.

## Reference source / commit / license

Own code.

## Completion criteria for the whole plan

All phases done, docs and CHANGELOG describe the new format and options.
