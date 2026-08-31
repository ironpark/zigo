---
description: Align example Go module requirements with the Go 1.24 CI toolchain.
plan_status: in-progress
registered_at: "2026-08-31T07:20:30Z"
---
> NEXT: Upgrade both CI jobs to Go 1.26.x and verify the workflow. ([Phase 0](phases/00-initial-work.md))

# Phases

- [ ] [Phase 00: Initial Work](phases/00-initial-work.md)

# Shared Verification

Confirm both `actions/setup-go` steps select Go 1.26.x, ensure no Go 1.24.x selector remains in the workflow, parse the YAML, and run `git diff --check`.

# Decisions That Constrain Ordering

The single phase is independent and atomic.

# Next Implementation Target

Upgrade both CI jobs to Go 1.26.x and verify the workflow.
