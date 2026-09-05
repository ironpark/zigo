---
description: Publish the generated-code quality and hygiene work as 0.11.0
plan_status: in-progress
registered_at: "2026-09-05T23:54:08Z"
---
> NEXT: Release 0.11.0. ([Phase 0](phases/00-release.md))

# Phases

- [ ] [Phase 00: Release 0.11.0](phases/00-release.md)

# Shared Verification

- `zig build test --summary all`; `zig fmt --check`; all examples `go-check`/`purego-go-check`.

# Decisions That Constrain Ordering

Single phase.

# Next Implementation Target

Release 0.11.0.
