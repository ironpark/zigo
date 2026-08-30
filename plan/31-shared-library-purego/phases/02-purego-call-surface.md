---
depends_on:
- "31-shared-library-purego#1"
perf_phase: false
status: planned
---
> DONE-WHEN: The representative module passes `CGO_ENABLED=0 go test ./...` against the generated shared
> NEXT: none

# Callback-Free purego Call Surface

## Planned Work

- Generate purego ABI function variables and raw wrappers for all existing callback-free lowering:
  fixed-width and pointer-sized integers, floats, bool-as-u8, opaque handles, nullable pointers,
  input/output slices, error unions, panic messages, enums, and tagged-union projections.
- Preserve public ownership, `Close`, borrowed reference, checked projection, auto-cleanup, and typed
  error behavior while removing every `import "C"` and `runtime/cgo` dependency from purego output.
- Add a representative purego example and golden fixtures, including empty slices, null handles,
  native panic, stale generation, and ABI-diff coverage.

## Done When

- The representative module passes `CGO_ENABLED=0 go test ./...` against the generated shared
  library, contains no cgo imports or directives, and matches the cgo backend's observable public API
  and behavior for every callback-free supported type category.
