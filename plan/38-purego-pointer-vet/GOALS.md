# GOALS

## Problem and the end result from the user's point of view

`go vet ./...` on a generated purego package reports `possible misuse of unsafe.Pointer` in
`LastErrorMessage`, which walks the native message by converting `uintptr + offset` back into an
`unsafe.Pointer` on every byte. That conversion is exactly the stale-pointer pattern vet warns
about, and a generated package that a user cannot vet cleanly forces them to either ignore the
finding or exclude the package from their own checks. The end result: every generated purego
package passes `go vet` with no findings and no suppression.

## Measurable goals

- `CGO_ENABLED=0 go vet ./...` reports nothing for every generated purego package.
- The message is read with typed pointer arithmetic that never round-trips through `uintptr`.
- The purego raw wrappers stop emitting an identity `unsafe.Pointer` conversion of a value that is
  already an `unsafe.Pointer`.
- Behavior is unchanged: an absent message is still the empty string, and a message is still copied
  out of native memory before it is returned.

## Supported scope and non-goals

- Only the generated purego raw layer changes. The cgo backend keeps its `C.GoString` conversion,
  where the conversion from a C pointer type is required.
- Do not change the C ABI, the exported symbol set, the public Go API, or the loader contract.
- Do not add vet suppressions, build tags, or lint configuration; fix the pattern instead.

## Reference source / commit / license

- `purego v0.10.2` binds a return value of kind `reflect.UnsafePointer` directly, and its own
  `func.go` uses the same trick to keep vet quiet.
- `unsafe.Add` and `unsafe.Slice` are available from Go 1.17; the generated modules require 1.23.

## Completion criteria for the whole plan

- Every purego example regenerates, vets clean, and passes `CGO_ENABLED=0 go test ./...`, including
  the native panic paths that produce a message.
