# GOALS

## Problem and the end result from the user's point of view

Generated public Go types currently share `<package>_gen.go` with function bodies. Generate them in a dedicated `<package>_type_gen.go` file so the public package layout has one stable responsibility per generated file.

## Measurable goals

- Emit enum, callback, opaque handle, reference, and handle lifecycle declarations in `<package>_type_gen.go`.
- Keep callable wrappers in `<package>_gen.go`, errors in `<package>_errors_gen.go`, and private support in `<package>_helpers_gen.go`.
- Include the new file in formatting, source update, stale-generation checking, and atomic generation tests.

## Supported scope and non-goals

This changes generated file placement only. It does not rename Go types, alter public signatures, change ABI lowering, or split each individual type into a separate file.

## Reference source / commit / license

Repository implementation at commit `6c9e534`; no external source is copied.

## Completion criteria for the whole plan

All fixtures and examples contain `<package>_type_gen.go`, old public files no longer define public types, documentation matches the layout, and root plus example verification passes.
