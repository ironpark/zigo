---
depends_on:
- "56-windows-purego-support#0"
perf_phase: false
status: planned
---
> DONE-WHEN: CI is green on both runners; the Windows job demonstrably exercises both
> NEXT: none

# Windows CI job with native and cross-built DLLs

## Planned Work

- Add a `windows-latest` job to `.github/workflows/ci.yml`: install Zig and
  Go, build the example shared libraries natively, run the purego example
  suites with `CGO_ENABLED=0` (and `ZIGO_TEST_LIBRARY` where the suite
  needs it).
- Add the cross-compile proof: build one example's DLL with
  `-Dtarget=x86_64-windows` on the Ubuntu job, hand it to the Windows job
  (artifact), and run that example's suite against it.
- Keep Ubuntu jobs unchanged; document the CI matrix decision (partially
  reversing plan 45) in the workflow file comment.

## Done When

- CI is green on both runners; the Windows job demonstrably exercises both
  the natively-built and the cross-built DLL; total added CI time is
  reported in the phase notes.
