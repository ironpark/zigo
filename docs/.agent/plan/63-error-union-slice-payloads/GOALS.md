# GOALS

## Problem and the end result from the user's point of view

Plan 61 phase 4 added caller-owned slice returns with a release function, but
only for plain `[]T` returns. An error-union payload slice (`![]T`,
`![]const T`) hits `error.UnsupportedType` in `lowerValue`, because the error
branch lowers one `out_result` scalar and has no pointer-plus-length path. The
dogfooding case that motivated the feature is a fallible decoder returning a
native-allocated buffer, so without `![]T` the release feature is half useful.
After this plan, `pub fn decode(...) ![]f32` generates `func (...) ([]float32,
error)` on cgo and purego, the payload is a Go-owned copy, and with
`.returns = .caller` plus `.release` the native buffer is freed right after the
copy, only on success.

## Measurable goals

- `![]T` and `![]const T` returns lower to `int32` code plus `out_result_ptr`
  and `out_result_len`; the shim writes them only on success.
- Public Go signature is `([]T, error)`; on error the slice is nil and no
  release is called.
- `.returns = .caller` with `.release` works for error-union slice payloads
  exactly as for plain slice returns; ZIGO016 checks apply unchanged.
- Element types: scalars, enums, and extern structs (plan 61 phase 1).
- `zig build test`, example checks on both backends, and `abi-check` stay
  green; the `![]T` gap note is removed from `bindings.md` and
  `limitations.md`.

## Supported scope and non-goals

In scope: lowering, shim, cgo raw, purego raw, public layer, abi_diff equality,
validate paths that inspect error-union payloads, generator-case goldens, an
example fixture with a leak counter, docs.

Non-goals: `![]string` or string-slice returns; `!?[]T`; slices of opaque
handles; error-union payloads of tagged-union projections.

## Reference source / commit / license

Repository at HEAD `76ec346` (plans 61 and 62 done). Plan 61 phase 4
(`836691f`) is the reference implementation for release plumbing. MIT.

## Completion criteria for the whole plan

Both phases done, the fixture round-trips on cgo and purego with the leak
counter back at zero, goldens and docs updated, committed.
