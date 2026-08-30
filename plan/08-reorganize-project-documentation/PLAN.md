---
description: Reorganize design docs, simplify README, and move detailed usage and limitations into wiki-style documentation.
plan_status: in-progress
registered_at: "2026-08-30T02:29:01Z"
---
> NEXT: Start by organizing the existing design documentation. ([Phase 0](phases/00-organize-design-documentation.md))

# Phases

- [x] [Phase 00: Organize design documentation](phases/00-organize-design-documentation.md)
- [ ] [Phase 01: Create concise README and wiki](phases/01-create-readme-and-wiki.md)

# Shared Verification

Search for stale documentation paths, validate every relative Markdown link with a local script, check formatting, and run the relevant Zig build/test command for retained examples.

# Decisions That Constrain Ordering

Move design files first so the README and wiki can link directly to their final locations.

# Next Implementation Target

Start by organizing the existing design documentation.
