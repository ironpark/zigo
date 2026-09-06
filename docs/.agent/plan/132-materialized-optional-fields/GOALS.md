# GOALS

## Problem and the end result from the user's point of view

A materialized result tree rejects `?i32` or `?[]const u8` fields with
`ZIGO048`, so a struct with an absent-able number or string cannot be
returned as a snapshot. Reflection already produces the `optional` node for
them; only validation, layout, encoder and decoder lack a representation.

After this plan such fields are accepted. The Zig walker writes presence and
value into the field's existing 16-byte slot, and the Go snapshot exposes
them as `*T` and `*string`, nil when absent.

## Measurable goals

- `?bool`, `?int`, `?float`, `?enum` and `?[]const u8` fields validate,
  encode and decode on both backends.
- The `materialized` snapshot case and example 12 carry such fields and
  their round trips pass.
- Other optionals (`?[]T`, `?[]string`, `??T`, `?Node`) keep a clear
  `ZIGO048` reason.

## Supported scope and non-goals

Optional scalar and optional string fields only. No optional slices or
embedded nodes; optional node pointers already exist.

## Reference source / commit / license

Own code.

## Completion criteria for the whole plan

`zig build test` passes, example 12 (cgo and purego) passes `go test`, docs
and CHANGELOG describe the new field shapes.
