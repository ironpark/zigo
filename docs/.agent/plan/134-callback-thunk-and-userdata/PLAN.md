---
description: Shim thunk adapts bool callbacks and declared userdata positions; validate enforces the userdata contract
plan_status: in-progress
registered_at: "2026-09-06T06:31:46Z"
---
> NEXT: Bool callbacks through the shim thunk. ([Phase 0](phases/00-bool-thunk.md))

# Phases

- [ ] [Phase 00: Bool callbacks through the shim thunk](phases/00-bool-thunk.md)
- [ ] [Phase 01: Declared userdata position](phases/01-userdata-index.md)
- [ ] [Phase 02: Docs](phases/02-docs.md)

# Shared Verification

`zig build test`; regenerate snapshot cases; compile a scratch cgo and purego example carrying a bool callback with userdata first.

# Decisions That Constrain Ordering

Phase 0 first so phase 1 reuses the generalized thunk predicate; docs last.

# Next Implementation Target

Bool callbacks through the shim thunk.
