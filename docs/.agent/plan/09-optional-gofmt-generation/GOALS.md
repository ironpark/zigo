# GOALS

## Problem and the end result from the user's point of view

Generated Go files should be passed through `gofmt` automatically when that executable is available, while generation must continue normally on hosts without it.

## Measurable goals

- Detect `gofmt` from the build environment without making Go a mandatory generator dependency.
- Format both raw/cgo and public generated Go files before source update and stale comparison.
- Keep Zig cache outputs immutable and preserve behavior when `gofmt` is absent.

## Supported scope and non-goals

This covers Go source formatting in `addGoBindings`; installing Go or formatting user-owned Go files is out of scope.

## Reference source / commit / license

The implementation is based on the current repository; no external source is copied.

## Completion criteria for the whole plan

The build graph shows two successful `gofmt` runs when available, generated sources remain synchronized, root and example tests pass, and documentation describes the optional behavior.
