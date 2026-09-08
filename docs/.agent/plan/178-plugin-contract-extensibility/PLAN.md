---
completed_at: "2026-09-08T05:09:30Z"
description: Public plugin contract, built-in isolation, analysis and complete public hooks
plan_status: done
registered_at: "2026-09-08T04:34:39Z"
---
> NEXT: Implement the compatible contract foundation. ([Phase 0](phases/00-contract-foundation.md))

# Phases

- [x] [Phase 00: Contract foundation](phases/00-contract-foundation.md)
- [x] [Phase 01: Built-in isolation and analysis](phases/01-builtin-isolation.md)
- [x] [Phase 02: Public hooks and verification](phases/02-public-hooks.md)

# Shared Verification

Use zig build test and zig build check, targeted tests during development, external plugin fixtures and unchanged golden ABI artifacts.

# Decisions That Constrain Ordering

User explicitly prefers a clean breaking API over compatibility. Foundation precedes isolated built-ins, then hook completion and integration verification.

# Next Implementation Target

Implement the compatible contract foundation.
