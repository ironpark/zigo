# SCOPE

Update build/emitter path computation, generator tests, the colocated example artifact, and user documentation.

# CONTEXT

## Current implementation and bottlenecks

Both the build update step and emitter currently construct `<package>_raw_gen.go`, and tests/docs encode that name.

## Target structure and invariants

Colocated output uses `<package>_cgo_gen.go`; separate raw packages continue using `<package>_gen.go`. The colocated file remains in the same directory and Go package as the public wrapper but remains physically separate.
