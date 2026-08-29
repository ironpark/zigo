---
description: Keep intentional snapshot mismatch coverage without leaking stderr into successful zig build test logs.
plan_status: in-progress
registered_at: "2026-08-29T21:55:13Z"
---
> NEXT: Make snapshot mismatch rendering capturable and clean the successful test output. ([Phase 0](phases/00-initial-work.md))

# Phases

- [ ] [Phase 00: Initial Work](phases/00-initial-work.md)

# Shared Verification

- `zig test tests/snapshot.zig`
- `zig build test`
- Capture stdout/stderr from a plain `zig build test` and assert it is empty on success.

# Decisions That Constrain Ordering

The single phase updates the renderer and its direct caller together, then verifies the repository-wide test step.

# Next Implementation Target

Make snapshot mismatch rendering capturable and clean the successful test output.
