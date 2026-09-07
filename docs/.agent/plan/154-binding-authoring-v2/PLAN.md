---
description: Implement a typed declaration tree and normalized binding authoring API
plan_status: in-progress
registered_at: "2026-09-07T12:44:16Z"
---
> NEXT: Implement the typed authoring contracts and scoped references. ([Phase 0](phases/00-contracts-and-references.md))

# Phases

- [x] [Phase 00: Typed authoring contracts and references](phases/00-contracts-and-references.md)
- [ ] [Phase 01: Declaration tree normalization](phases/01-normalize-tree.md)
- [ ] [Phase 02: Switch public API and migrate consumers](phases/02-migrate-consumers.md)
- [ ] [Phase 03: Documentation and final verification](phases/03-docs-and-verification.md)

# Shared Verification

Use meaningful unit/compile-fail tests, full zig build test, and example generation checks. Check both successful normalization and rejected invalid inputs. Keep source and plan commits aligned per phase.

# Decisions That Constrain Ordering

Contracts and references, then normalization, consumer migration, documentation and final checks.

# Next Implementation Target

Implement the typed authoring contracts and scoped references.
