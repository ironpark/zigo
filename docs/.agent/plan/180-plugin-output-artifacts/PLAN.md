---
completed_at: "2026-09-08T06:19:01Z"
description: Separate framed Go files from exact-byte artifacts with explicit package targets and emission scopes.
plan_status: done
registered_at: "2026-09-08T05:49:42Z"
---
> NEXT: Implement and verify separate framed Go files and exact-byte artifacts. ([Phase 0](phases/00-output-contracts.md))

# Phases

- [x] [Phase 00: Output contracts](phases/00-output-contracts.md)

# Shared Verification

Run zig build test -j4 and zig build check -j4, changed-file Zig and Go formatting checks and git diff --check. Exercise invalid paths and build constraints, disabled plugins and split packages.

# Decisions That Constrain Ordering

One coherent contract migration; the previous contract and transform plans are complete.

# Next Implementation Target

Implement and verify separate framed Go files and exact-byte artifacts.
