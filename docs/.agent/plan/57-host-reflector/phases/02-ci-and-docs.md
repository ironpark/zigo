---
depends_on:
- "57-host-reflector#1"
perf_phase: false
status: planned
---
> DONE-WHEN: CI green on both runners with the artifact leg exercising the
> NEXT: none

# Cross-build CI leg and docs

## Planned Work

- Ubuntu CI job: add a step cross-building 07-event-queue's Windows DLL
  and uploading it as an artifact; Windows job: download it and run the
  07 suite against it via `ZIGO_TEST_LIBRARY` in addition to its native
  legs.
- Update docs: cross-compile recipe (`zig build go-lib -Dtarget=...` per
  OS), remove the plan-56 "cross-compilation unsupported" limitation,
  document the host-reflection semantics (target-conditional surfaces
  unsupported; layout divergence caught at target compile time by the
  guards).

## Done When

- CI green on both runners with the artifact leg exercising the
  cross-built DLL; docs updated; no stale limitation text;
  `planr overview` shows the plan done.
