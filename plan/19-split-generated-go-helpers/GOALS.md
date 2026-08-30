# GOALS

## Problem and the end result from the user's point of view

Generated public API files still contain private conversion and callback-lifecycle helpers. Large packages should place this runtime support in a predictable package-named generated file.

## Measurable goals

- Emit `<package>/<package>_helpers_gen.go` alongside API and error files.
- Move `boolToUint8`, callback handle state, and callback handle lifecycle/test helpers without changing identifiers or behavior.
- Keep main-file imports minimal and preserve separate and colocated raw-package compilation.

## Supported scope and non-goals

This changes emitter boundaries, build formatting/update inputs, golden fixtures, examples, and generated-layout documentation. Error conversion remains in `_errors_gen.go`; handle types, `Close`, enums, and public functions remain in `_gen.go`.

## Reference source / commit / license

Repository generator behavior at `7f9e6a3`; no external source is copied.

## Completion criteria for the whole plan

All helper declarations appear only in `_helpers_gen.go`; generator/golden tests, all example stale/ABI/Go checks, root tests, formatting, native and Windows compilation pass; unrelated user work remains untouched.
