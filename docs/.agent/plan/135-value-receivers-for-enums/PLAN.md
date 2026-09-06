---
description: Allow registered enums to be method receivers so wrapper free functions and .covers disappear
plan_status: in-progress
registered_at: "2026-09-06T14:05:56Z"
---
> NEXT: Teach reflection to resolve a registered enum as a value receiver and carry the ([Phase 0](phases/00-reflect-enum-receivers.md))

# Phases

- [x] [Phase 00: Reflect enum receivers](phases/00-reflect-enum-receivers.md)
- [x] [Phase 01: Reject what a value receiver cannot mean](phases/01-value-receiver-diagnostics.md)
- [x] [Phase 02: Emit value-receiver methods](phases/02-emit-value-receiver.md)
- [ ] [Phase 03: Document and land](phases/03-document-and-land.md)

# Shared Verification

- `zig fmt --check build.zig src tests examples`
- `zig build test --summary all`
- `scripts/update-generator-cases.sh` produces no diff for existing cases.
- In the new case directories: `zig build go-check abi-check`, `go test ./...`,
  and `CGO_ENABLED=0 go test ./...` for the purego twin.
- `go-coverage` on the enum-receiver fixture reports the methods bound with no
  `.covers` entry.

# Decisions That Constrain Ordering

Phase 0 makes the receiver reachable and observable in `semantic.json` before
anything is emitted, so a mistake there shows up as a document diff rather than
as broken Go. Phase 1 lands the rejections before the emitter has to survive the
shapes they exclude. Phase 2 is the only phase that changes generated output.
Phase 3 follows the emitter so the docs describe what shipped.

# Next Implementation Target

Teach reflection to resolve a registered enum as a value receiver and carry the
