---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Prototype checks pass, limits and integration steps are documented, and production files remain unchanged.
> NEXT: none

# Initial Work

## Planned Work

- Compare design alternatives, build an isolated generic context prototype, validate representative existing declarations, and write a recommendation.

## Done When

- Prototype checks pass, limits and integration steps are documented, and production files remain unchanged.

## Research Results and Verification

- Recommended optional Entry.context() returning a generic type with captured source scope, target reference and original Entry, lowering via define/select to the existing Entry schema.
- Compared direct Context returns, declaration-struct auto collection and explicit factory arguments; documented lexical @This boundaries and lifecycle/source identity.
- Added an isolated prototype and reproducer under docs/.agent/research/generic-binding-context.
- Seven positive tests and seven compile-failure checks passed with Zig 0.16.0.
- Temporary rewrites of callback, event-queue, io-streams and materialized have exact comptime deep equality with their existing normalized bindings.
- Existing production source and example files were not changed; runtime and compile-performance validation remain part of future implementation.
- git diff --check passed.
