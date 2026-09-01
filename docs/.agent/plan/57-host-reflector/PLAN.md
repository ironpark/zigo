---
completed_at: "2026-09-01T17:07:35Z"
description: "Cross-compile support: build the reflection pipeline for the host while the native library targets -Dtarget, with comptime ABI guards in the shim"
plan_status: done
registered_at: "2026-09-01T16:45:19Z"
---
> NEXT: Retarget the reflection pipeline to the host and remove the purego host gate. ([Phase 0](phases/00-host-pipeline.md))

# Phases

- [x] [Phase 00: Host-built reflection pipeline](phases/00-host-pipeline.md)
- [x] [Phase 01: Comptime ABI guards in the shim](phases/01-abi-guards.md)
- [x] [Phase 02: Cross-build CI leg and docs](phases/02-ci-and-docs.md)

# Shared Verification

- `zig build test` and `check` (native + windows cross-check) after every
  phase; ten cgo + four purego trees locally.
- Phase 0: cross go-lib builds + export-table listing + zero Go drift.
- Phase 1: divergence fixture red-for-windows/green-native; goldens.
- Phase 2: CI runs on both runners including the artifact leg.
- Grep checks: no `isRunnableOnHost` purego gate; guards present in every
  committed shim; docs no longer claim cross-compilation is unsupported.

# Decisions That Constrain Ordering

Phase 0 makes cross-builds possible; phase 1 makes them safe before
anything advertises the capability; phase 2 advertises and continuously
proves it. Strictly sequential.

# Next Implementation Target

Retarget the reflection pipeline to the host and remove the purego host gate.
