---
completed_at: "2026-09-05T10:51:22Z"
description: Fix stream reader contracts and harden materialized allocation and decoding paths
plan_status: done
registered_at: "2026-09-05T10:36:23Z"
---
> NEXT: Implement and verify boundary hardening. ([Phase 0](phases/00-initial-work.md))

# Phases

- [x] [Phase 00: Initial Work](phases/00-initial-work.md)

# Shared Verification

Run Zig unit/snapshot tests, example generation checks, cgo/purego Go tests and race checks. Exercise allocation failures and malformed decoder counts.

# Decisions That Constrain Ordering

Stream fixes, materialized hardening, diagnostics and CI, then complete verification.

# Next Implementation Target

Implement and verify boundary hardening.
