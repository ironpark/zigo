---
description: Fix enum/handle callback params in cgo shim trampolines and reject unsupported callback parameter types with a diagnostic
plan_status: in-progress
registered_at: "2026-09-07T06:59:12Z"
---
> NEXT: Fix shim spelling, add the validation rule, cases, and docs. ([Phase 0](phases/00-shim-and-validation.md))

# Phases

- [ ] [Phase 00: Shim spelling and validation](phases/00-shim-and-validation.md)

# Shared Verification

`zig build test`, `scripts/update-generator-cases.sh callback_enum_handle callback_enum_handle_purego`, and a manual `zig build-obj` of each new shim against a stub `zigo_target` module.

# Decisions That Constrain Ordering

Single phase.

# Next Implementation Target

Fix shim spelling, add the validation rule, cases, and docs.
