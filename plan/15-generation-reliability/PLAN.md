---
completed_at: "2026-08-30T04:50:42Z"
description: Make generation transactional, harden errors.lock transitions, expose reflection enrichment failures, and expand complex golden coverage.
plan_status: done
registered_at: "2026-08-30T04:39:05Z"
---
> NEXT: Prepare every artifact before the generator mutates its output directory. ([Phase 0](phases/00-transactional-artifact-preparation.md))

# Phases

- [x] [Phase 00: Transactional artifact preparation](phases/00-transactional-artifact-preparation.md)
- [x] [Phase 01: Safe errors.lock state transitions](phases/01-safe-errors-lock-transitions.md)
- [x] [Phase 02: Transparent reflection enrichment](phases/02-transparent-reflection-enrichment.md)
- [x] [Phase 03: Complex golden coverage and documentation](phases/03-complex-golden-and-docs.md)

# Shared Verification

Run phase-focused filtered Zig tests, `zig build test --summary all`,
`zig build check -Dtarget=x86_64-windows`, `zig fmt --check build.zig src tests
examples`, `git diff --check`, and Go tests for the complex pipeline example.

# Decisions That Constrain Ordering

The transaction boundary comes first so all later failures are safely tested.
Lock validation then becomes another pre-commit invariant. Reflection diagnostics
are independent at runtime but follow for a simple commit history. The final
golden fixture is generated only after all behavior is stable.

# Next Implementation Target

Prepare every artifact before the generator mutates its output directory.
