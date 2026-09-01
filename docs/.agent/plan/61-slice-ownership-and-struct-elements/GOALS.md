# GOALS

## Problem and the end result from the user's point of view

A dogfooding library hit three lowering gaps that force opaque-handle
workarounds for plain data: (1) an out parameter `out: []OffsetEstimate` whose
element is an all-scalar `extern struct` is rejected with `ZIGO013`; (2) a
`paths: []const [:0]const u8` parameter is rejected because the element holds a
pointer; (3) a native-allocated result slice (`![]f32`, caller must free) has no
representation, since out slices are caller-buffer only. After this plan, all
three declare directly: scalar-only extern structs are legal slice elements on
both backends, string slices lower to `[]string`, and `.returns = .caller` on a
slice return plus a registered release function makes the generated Go copy the
data and free the native buffer in one call.

Two latent bugs found during review block (3) and are fixed first: the cgo raw
layer returns every slice through `C.GoBytes` (compile error and byte/element
length confusion for non-`u8` elements), and the purego raw layer returns an
`unsafe.Slice` alias of native memory instead of a copy.

## Measurable goals

- `extern struct` with only ZIGO012-eligible fields is accepted as a slice
  element for in and out parameters and for slice returns; cgo and purego
  goldens compile and round-trip values.
- `[*:0]const u8`, `[]const [*:0]const u8`, `[]const [:0]const u8`, and
  `[]const []const u8` with `.semantic = .utf8_string` lower to `string` /
  `[]string` on both backends without Go pointers entering C memory.
- `.returns = .caller` on a slice (direct or error-union payload) with a
  `.release` entry generates copy-then-free Go; missing or mismatched release is
  a diagnostic, never broken Go.
- Non-`u8` slice returns compile on cgo and are Go-owned copies on purego.
- `zig build test`, every example's `test go-check abi-check` and Go tests, and
  the purego example suite stay green.

## Supported scope and non-goals

In scope: validate/lower/emit changes for the three features, reflector support
for sentinel-terminated `u8` many-pointers, ABI metadata and `abi-check`
classification for the new release symbol, generator-case goldens, one example
exercising each feature on cgo and purego, and design/user docs (03 §3, §6,
`limitations.md`, `bindings.md`).

Non-goals: extern structs inside optionals or callback signatures (still
`ZIGO013`); pointer-bearing fields inside extern structs (still `ZIGO012`,
follow-up plan); non-`u8` sentinel pointers; `[]string` returns; slices of
opaque handles; changing the value-struct append ABI policy.

## Reference source / commit / license

Repository at HEAD `7da72f2`. Review notes are in the conversation that created
this plan; the same findings are restated in CONTEXT. MIT, no external source.

## Completion criteria for the whole plan

All five phases done, docs updated, goldens regenerated and committed, and the
three dogfooding declarations from the review (`estimate`, `extractPaths`
string-slice parameter, caller-owned `[]f32` return with release) each have an
equivalent fixture that generates and passes on both backends.
