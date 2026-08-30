---
completed_at: "2026-08-30T13:04:06Z"
perf_phase: false
status: done
---
> DONE-WHEN: Native macOS/Linux dynamic fixtures prove artifact installation, symbol visibility, dependency
> NEXT: none

# Shared Library Artifact Contract

## Planned Work

- Add build-graph fixtures for `.dynamic` and assert target-specific library name, installed location,
  exported zigo wrapper symbols, absence of unintended unresolved Go symbols, and loadability.
- Define macOS/Linux runtime naming and dependency policy, including macOS install name and Linux
  SONAME/RPATH expectations. Expose the emitted shared artifact and a standard build step without
  changing static/cgo defaults.
- Add a tiny host-side smoke loader that resolves and calls scalar, error, and panic-translation
  symbols directly from the installed library.

## Done When

- Native macOS/Linux dynamic fixtures prove artifact installation, symbol visibility, dependency
  resolution, successful calls, and expected missing-library/wrong-symbol failures; all static cgo
  tests remain unchanged.
