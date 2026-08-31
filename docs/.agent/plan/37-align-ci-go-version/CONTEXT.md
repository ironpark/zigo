# SCOPE

Update `examples/01-scalar/go/go.mod` and `examples/02-errors/go/go.mod` from Go 1.26 to Go 1.24.

# CONTEXT

## Current implementation and bottlenecks

Both CI jobs install Go 1.24.x with `GOTOOLCHAIN=local`, while two checked-in example modules specify Go 1.26.

## Target structure and invariants

Example module minimum versions do not exceed the CI toolchain; no dependency or generated source changes are introduced.
