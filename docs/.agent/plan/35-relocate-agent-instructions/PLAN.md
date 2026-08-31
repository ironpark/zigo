---
description: Move planr guidance under docs/.agent, update AGENTS.md, and add a CLAUDE.md symlink.
plan_status: in-progress
registered_at: "2026-08-31T07:13:28Z"
---
> NEXT: Relocate the agent guidance and add the cross-tool instruction symlink. ([Phase 0](phases/00-initial-work.md))

# Phases

- [ ] [Phase 00: Initial Work](phases/00-initial-work.md)

# Shared Verification

Run `test -f docs/.agent/tool.md`, confirm root `tool.md` is absent, inspect `AGENTS.md`, validate `CLAUDE.md` with `test -L` and `readlink`, and review `git status --short` plus the staged diff before committing.

# Decisions That Constrain Ordering

The single phase has no dependencies and performs the complete atomic relocation.

# Next Implementation Target

Relocate the agent guidance and add the cross-tool instruction symlink.
