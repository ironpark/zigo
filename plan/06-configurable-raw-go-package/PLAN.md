---
completed_at: "2026-08-30T02:08:21Z"
description: Allow generated raw Go bindings to stay under internal/raw, move to a custom relative package path, or colocate safely with the public package.
plan_status: done
registered_at: "2026-08-30T02:02:18Z"
---
> NEXT: Implement and verify configurable raw-package placement end to end. ([Phase 0](phases/00-configurable-raw-placement.md))

# Phases

- [x] [Phase 00: Configurable raw package placement](phases/00-configurable-raw-placement.md)

# Shared Verification

Run the root Zig test suite, run `zig build go go-check abi-check --summary all` and `go test -count=1 ./...` in each example, inspect generated-file paths, and run `git diff --check`.

# Decisions That Constrain Ordering

The single phase changes the public option and every consumer atomically because partial adoption would make the build runner and generator CLI disagree.

# Next Implementation Target

Implement and verify configurable raw-package placement end to end.
