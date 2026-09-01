# GOALS

## Problem and the end result from the user's point of view

The generated public type file is a monolith. In example 10,
`tagged_union_type_gen.go` is 1,023 lines / 122 functions mixing five
concerns: enums (~10%), handle/ref lifecycle (~18%), the fixed zigo runtime
(~5%), and tagged-union projections/snapshots/variants (~65%, growing with
every union). Meanwhile `<pkg>_helpers_gen.go` is 9 lines. After this plan the
generator emits concern-based files — enums, handles, runtime, and one file
per tagged union — so generated packages read like hand-laid-out Go
(one file per major type) and the largest section scales per union instead of
accreting into one file. Generated code content is unchanged; only file
placement moves.

## Measurable goals

- `<pkg>_type_gen.go` no longer exists in any regenerated tree; its content
  is distributed across `<pkg>_enums_gen.go`, `<pkg>_handles_gen.go`,
  `<pkg>_runtime_gen.go` (absorbing today's `<pkg>_helpers_gen.go`), and
  `<pkg>_union_<union>_gen.go` per tagged union.
- Example 10 emits exactly two union files (value, signal); no generated file
  in example 10's public package exceeds ~450 lines.
- Concatenated generated content per package is declaration-for-declaration
  identical to before the split (order within a concern preserved); only file
  boundaries and per-file import blocks differ.
- Examples without enums/unions emit no enum/union files (plan-49 no-empty-
  file rule holds per new file).
- All ten examples (cgo and purego) pass `go test`, `gofmt -l`, `go vet`;
  `zig build test` passes with updated goldens.

## Supported scope and non-goals

In scope: public-package emission paths in `src/gen/emit.zig` (path helpers
at emit.zig:67-93 and the per-section render passes), file-name collision
handling in `src/gen/naming.zig`, golden fixtures, `generator.zig` file-
presence tests, and regeneration of all examples. Non-goals: any change to
generated declarations or behavior, splitting the `internal/raw` package or
`<pkg>_gen.go` (operations file), and the errors file (already separate).

## Reference source / commit / license

Repository-local work on `main` (starting after plan 51, commit d88bc83).
Layout reference: Go standard library one-file-per-major-type convention.

## Completion criteria for the whole plan

All phases done; `zig build test` and all fourteen example Go trees green;
`planr overview` shows the plan complete.
