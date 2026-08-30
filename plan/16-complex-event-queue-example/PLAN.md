---
completed_at: "2026-08-30T05:00:33Z"
description: Add a second application-shaped Zig/Go example covering a stateful event queue, UTF-8 metadata, typed errors, enums, slices, and retained callbacks.
plan_status: done
registered_at: "2026-08-30T04:54:02Z"
---
> NEXT: Implement and validate the standalone event queue example end to end. ([Phase 0](phases/00-complex-event-queue.md))

# Phases

- [x] [Phase 00: Complex event queue example](phases/00-complex-event-queue.md)

# Shared Verification

Run the example Zig test, generation update/check and ABI step, its Go tests, root
`zig build test --summary all`, Windows compile check, Zig formatting, YAML/diff
checks, and verify regeneration leaves the worktree unchanged.

# Decisions That Constrain Ordering

Implement and test the Zig API first, generate bindings next so the Go API is
observed rather than guessed, then add Go tests and documentation before the final
repository-wide verification.

# Next Implementation Target

Implement and validate the standalone event queue example end to end.
