---
completed_at: "2026-09-01T15:00:40Z"
depends_on:
- "56-windows-purego-support#0"
perf_phase: false
status: done
---
> DONE-WHEN: CI is green on both runners; the Windows job builds every purego example's
> NEXT: none

# Windows CI job with native and cross-built DLLs

## Planned Work

- Add a `windows-latest` job to `.github/workflows/ci.yml`: install Zig and
  Go, build the example shared libraries natively, run the purego example
  suites with `CGO_ENABLED=0` (and `ZIGO_TEST_LIBRARY` where the suite
  needs it).
- Drop the cross-built-DLL artifact proof. Phase 0 established that
  `zig build go-lib -Dtarget=x86_64-windows` cannot run on a POSIX host:
  generation executes `zigo-reflect`, which `addGoBindings` builds for the
  requested target, so a non-native target fails before the library links.
  This is pre-existing and backend-independent, so the Windows job builds its
  DLLs natively and phase 2 documents the limitation instead.
- Keep Ubuntu jobs unchanged; document the CI matrix decision (partially
  reversing plan 45) in the workflow file comment.

## Done When

- CI is green on both runners; the Windows job builds every purego example's
  DLL natively and runs its suite against it; total added CI time is reported
  in the phase notes.

## Notes

- Example selection: 04-callback is excluded from the Windows job because it
  links system zlib (`linkSystemLibrary("z")`), which windows-latest does not
  provide; Zig fails with `unable to find dynamic system library 'z'`.
  07-event-queue and 08-telemetry-hub both emit `callbackPointers`, so
  `purego.NewCallback` on Windows is still covered, and 10-tagged-union keeps
  the explicit `ZIGO_TEST_LIBRARY` / `ZIGO_TEST_WRONG_LIBRARY` path coverage
  (its wrong-library slot points at the telemetry-hub DLL instead of the
  callback one).
- `core.autocrlf false` is set before checkout: `go-check` compares the bytes
  the generator produces against the committed tree, and the runner's default
  CRLF rewrite would report every generated file as stale.
- No cross-built DLL leg, per the phase-0 finding.
- Added CI time: not measured locally. The job is three example builds plus
  `zig build test`, run in parallel with the two Ubuntu jobs, so wall-clock CI
  time is bounded by the slowest job rather than extended. The real figure
  comes from the first run on GitHub.
- Verification limit: the job's command shapes were exercised on the macOS dev
  host with the POSIX library names; Windows runtime behaviour is unproven
  until this job runs on GitHub.
