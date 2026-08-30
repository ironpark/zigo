# GOALS

## Problem and the end result from the user's point of view

Generated public Go bindings currently mix package-level error declarations and conversion helpers into the main API file. Large bindings should keep those declarations in a predictable package-named generated file.

## Measurable goals

- Emit `<package>/<package>_errors_gen.go` alongside `<package>/<package>_gen.go`.
- Keep `Error`, stable `Err*` values, `ErrPanicCaught`, and `errorForCode` together in the error file.
- Preserve Go compilation for separate and colocated raw packages, including packages with no Zig error codes.

## Supported scope and non-goals

This changes generated public Go file placement, build-graph formatting/copy/check inputs, fixtures, examples, CI-visible generated artifacts, and documentation. It does not split errors by Zig error set or change `zigo/errors.lock.json`, codes, public identifiers, or runtime behavior.

## Reference source / commit / license

Repository generator behavior at `4ee6594`; no external source is copied.

## Completion criteria for the whole plan

Generator tests and golden fixtures prove the split; every example regenerates cleanly and passes Go tests; root Zig tests, formatting, native and Windows compilation, stale checks, and optional ABI checks pass.
