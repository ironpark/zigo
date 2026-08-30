---
depends_on:
- "31-shared-library-purego#0"
perf_phase: false
status: planned
---
> DONE-WHEN: Loader unit/integration tests cover success, repeat load, conflicting path, retry, missing file,
> NEXT: none

# Backend Model and Atomic purego Loader

## Planned Work

- Add the opt-in backend configuration and reject purego/static or unsupported target combinations
  with clear build errors. Thread backend identity and library metadata through CLI options, report,
  doctor, generated-file paths, and snapshots.
- Implement the purego raw runtime using `Dlopen`, checked `Dlsym`, and `RegisterFunc`; publish bound
  function variables only after every required symbol has resolved.
- Generate checked idempotent loading, retry after failed loads, environment/platform fallback
  discovery, typed `LibraryError`, and no-unload semantics. Pin purego `v0.10.2` when zigo creates a
  `go.mod`, and diagnose a missing dependency in existing modules.

## Done When

- Loader unit/integration tests cover success, repeat load, conflicting path, retry, missing file,
  wrong architecture where available, and missing symbol without partial state; `go-report` and
  `go-doctor` accurately distinguish cgo and purego prerequisites.
