---
completed_at: "2026-08-30T01:57:07Z"
description: Rename generated Go outputs to package-based *_gen.go files, migrate examples, and verify generation, sync checks, ABI checks, and Go tests.
plan_status: done
registered_at: "2026-08-30T01:53:00Z"
---
> NEXT: Rename generator-owned Go files and migrate every checked-in consumer. ([Phase 0](phases/00-rename-generated-go-outputs.md))

# Phases

- [x] [Phase 00: Rename generated Go outputs](phases/00-rename-generated-go-outputs.md)

# Shared Verification

Run root Zig tests; run generation, sync, ABI, and Go tests for all examples; search for legacy output paths; run `git diff --check`.

# Decisions That Constrain Ordering

The emitter, build graph, tests, and checked-in outputs form one atomic compatibility change and are handled in a single phase.

# Next Implementation Target

Rename generator-owned Go files and migrate every checked-in consumer.
