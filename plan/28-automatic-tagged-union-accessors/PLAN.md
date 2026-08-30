---
description: Generate safe tag and payload accessor bindings for opt-in tagged-union handles without exposing Zig union layout through the C ABI.
plan_status: in-progress
registered_at: "2026-08-30T10:19:39Z"
---
> NEXT: Implement semantic reflection and validation for the opt-in tagged-union handle representation. ([Phase 0](phases/00-initial-work.md))

# Phases

- [x] [Phase 00: Semantic reflection and validation](phases/00-initial-work.md)
- [x] [Phase 01: Checked accessor emission](phases/01-checked-accessor-emission.md)
- [ ] [Phase 02: End-to-end example and documentation](phases/02-example-and-documentation.md)

# Shared Verification

Run filtered Zig unit tests while developing, then `zig build test --summary all`. Run the example's Zig tests, binding generation/check, ABI check where configured, and `go test ./...`. Inspect generated header/shim/Go artifacts for pointer-only ABI and exercise wrong-variant access at runtime.

# Decisions That Constrain Ordering

Semantic data and validation precede emission. Emission precedes the checked-in example and user documentation so generated artifacts demonstrate the final contract.

# Next Implementation Target

Implement semantic reflection and validation for the opt-in tagged-union handle representation.
