# GOALS

## Problem and the end result from the user's point of view

Colocated low-level Go bindings should remain a separate file but use the clearer `<package>_cgo_gen.go` name instead of `<package>_raw_gen.go`.

## Measurable goals

- Rename every colocated generated path and expectation to `<package>_cgo_gen.go`.
- Keep the default `internal/raw/raw_gen.go` and custom-package `<raw_package>_gen.go` conventions unchanged.

## Supported scope and non-goals

This is a generated filename change only. Package layout, Go symbols, C ABI, and public wrapper behavior do not change.

## Reference source / commit / license

The implementation is based on repository commit `cfb7861`; no external source is copied.

## Completion criteria for the whole plan

The colocated example generates `scalar/scalar_cgo_gen.go`, all generator tests and example consistency checks pass, documentation reflects the new name, and the worktree is clean.
