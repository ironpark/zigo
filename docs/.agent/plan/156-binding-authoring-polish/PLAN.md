---
completed_at: "2026-09-07T13:58:41Z"
description: Implement concise contracts, member composition, contextual receivers, sparse callback metadata, and idiomatic examples/docs.
plan_status: done
registered_at: "2026-09-07T13:41:21Z"
---
> NEXT: Implement contract constructors and explicit contextual receiver selection. ([Phase 0](phases/00-contracts-and-members.md))

# Phases

- [x] [Phase 00: Contract helpers and contextual members](phases/00-contracts-and-members.md)
- [x] [Phase 01: Sparse callback contracts](phases/01-callback-contracts.md)
- [x] [Phase 02: Idiomatic examples and documentation](phases/02-examples-and-verification.md)

# Shared Verification

Zig formatting, full test/build checks, targeted positive/negative authoring tests, semantic/API comparisons and 13 example builds/Go tests including all purego modules.

# Decisions That Constrain Ordering

Contracts and member roles, then callbacks, then complete example cleanup/documentation and verification.

# Next Implementation Target

Implement contract constructors and explicit contextual receiver selection.
