---
completed_at: "2026-08-31T07:28:27Z"
perf_phase: false
status: done
---
> DONE-WHEN: `go vet` reports nothing for every generated purego package, the panic paths still return their
> NEXT: none

# Vet-Clean Native Message Reads

## Planned Work

- Bind the native error-message entry point as an `unsafe.Pointer` return and read the message with
  `unsafe.Add` and `unsafe.Slice` instead of `uintptr` arithmetic.
- Drop the identity `unsafe.Pointer` conversion from purego raw wrappers that return an opaque
  handle.
- Regenerate the purego examples and assert the vet-clean contract in the purego CI job.

## Done When

- `go vet` reports nothing for every generated purego package, the panic paths still return their
  message, and every purego example passes `CGO_ENABLED=0 go test ./...`.
