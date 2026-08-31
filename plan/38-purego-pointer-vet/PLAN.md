---
completed_at: "2026-08-31T07:28:27Z"
description: Read the native error message through typed pointer arithmetic so the generated purego package passes go vet
plan_status: done
registered_at: "2026-08-31T07:24:31Z"
---
> NEXT: Read the native message through typed pointer arithmetic. ([Phase 0](phases/00-vet-clean-pointers.md))

# Phases

- [x] [Phase 00: Vet-Clean Native Message Reads](phases/00-vet-clean-pointers.md)

# Shared Verification

- Zig: `zig build check` and `zig build test --summary all`, including an emitter assertion that no
  generated purego file converts a `uintptr` into an `unsafe.Pointer`.
- Go: `CGO_ENABLED=0 go vet ./...` and `CGO_ENABLED=0 go test ./...` for every purego example, plus
  the cgo matrix unchanged.
- Behavior: the tests that translate a Zig panic still observe the native message.

# Decisions That Constrain Ordering

Single phase.

# Next Implementation Target

Read the native message through typed pointer arithmetic.
