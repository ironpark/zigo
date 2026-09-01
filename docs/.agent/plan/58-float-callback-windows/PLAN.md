---
completed_at: "2026-09-01T18:10:46Z"
description: Support float callback parameters on Windows by bit-marshalling them uniformly across the purego callback ABI, retiring ZIGO014 and restoring 08 to the Windows CI job
plan_status: done
registered_at: "2026-09-01T17:41:36Z"
---
> NEXT: Lower float callback parameters to integer bit patterns on every platform. ([Phase 0](phases/00-bits-marshalling.md))

# Phases

- [x] [Phase 00: Uniform bit-marshalled float callback parameters](phases/00-bits-marshalling.md)
- [x] [Phase 01: Fidelity tests, CI restoration, docs](phases/01-fidelity-and-ci.md)

# Shared Verification

- `zig build test`/`check` (native + windows cross-check) after every
  phase; ten cgo + four purego trees locally; `GOOS=windows go
  vet/build` on purego trees.
- Phase 0: cross-build 08's windows DLL and list its export table; ABI
  recording check exercised (demonstrate the mismatch failure once,
  locally).
- Phase 1: Windows CI green including 08; fidelity assertions bit-exact.
- Grep checks: no ZIGO014 remnants inconsistent with the decision; no
  float-typed parameters in emitted callback typedefs/dispatchers; docs
  updated.

# Decisions That Constrain Ordering

Phase 0 lands the ABI change with local proof; phase 1 proves fidelity
and restores CI coverage, then rides the established CI loop.

# Next Implementation Target

Lower float callback parameters to integer bit patterns on every platform.
