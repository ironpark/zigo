---
completed_at: "2026-09-08T10:28:17Z"
description: Fix Windows-only deletion of published Go files caused by comparing manifest paths to walked paths
plan_status: done
registered_at: "2026-09-08T09:49:56Z"
---
> NEXT: Fix the comparisons and watch the Windows CI jobs. ([Phase 0](phases/00-portable-paths.md))

# Phases

- [x] [Phase 00: Portable path comparison](phases/00-portable-paths.md)

# Shared Verification

`zig build test --summary all` locally, then the Windows CI jobs on the pushed
commit.

# Decisions That Constrain Ordering

Single phase.

# Next Implementation Target

Fix the comparisons and watch the Windows CI jobs.
