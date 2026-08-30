---
completed_at: "2026-08-30T03:41:06Z"
description: Ignore local reference sources and clone the zls 0.16.x line into ref/zls for development reference.
plan_status: done
registered_at: "2026-08-30T03:40:11Z"
---
> NEXT: Ignore `ref/`, clone the verified zls 0.16.x ref, and validate the checkout. ([Phase 0](phases/00-add-ignored-zls-checkout.md))

# Phases

- [x] [Phase 00: Add ignored zls checkout](phases/00-add-ignored-zls-checkout.md)

# Shared Verification

Use `git check-ignore`, and inspect `git -C ref/zls remote`, branch/tag, status, and HEAD.

# Decisions That Constrain Ordering

Install the ignore rule before cloning so the reference tree never appears as project changes.

# Next Implementation Target

Ignore `ref/`, clone the verified zls 0.16.x ref, and validate the checkout.
