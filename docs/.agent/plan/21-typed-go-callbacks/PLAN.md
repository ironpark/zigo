---
completed_at: "2026-08-30T06:19:29Z"
description: Generate named Go callback types and signature-specific handle helpers instead of erasing callbacks to any.
plan_status: done
registered_at: "2026-08-30T06:09:48Z"
---
> NEXT: Implement stable public callback types and signature-specific typed handle helpers in the Go emitter. ([Phase 0](phases/00-typed-callback-emission.md))

# Phases

- [x] [Phase 00: Typed callback emission](phases/00-typed-callback-emission.md)
- [x] [Phase 01: Fixtures and documentation](phases/01-fixtures-and-documentation.md)
- [x] [Phase 02: Full compatibility verification](phases/02-full-compatibility-verification.md)

# Shared Verification

- `zig build test`, `zig build check`, and `zig build check -Dtarget=x86_64-windows-gnu` pass.
- Callback golden fixtures contain defined callback types and typed helpers with unnamed storage conversion.
- All eight examples pass `go-check`, `abi-check`, and Go tests; examples with Zig test steps also pass them.
- `zig fmt --check .` and `git diff --check` pass.

# Decisions That Constrain Ordering

The generator contract and tests land before checked-in examples and documentation are regenerated. Full compatibility verification follows all generated-source changes.

# Next Implementation Target

Implement stable public callback types and signature-specific typed handle helpers in the Go emitter.
