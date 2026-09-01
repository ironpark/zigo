---
depends_on:
- "56-windows-purego-support#0"
perf_phase: false
status: planned
---
> DONE-WHEN: No doc or generated message claims purego is macOS/Linux-only; the
> NEXT: none

# Cross-compile documentation and platform docs sweep

## Planned Work

- Document the Windows + cross-compile story in `docs/bindings.md` (and
  README where platforms are mentioned): supported platforms table, DLL
  naming, `zig build go-lib -Dtarget=...` recipes for the three OS targets,
  `GOOS=windows go build` needing no C toolchain, and the note that cgo on
  Windows is unsupported (with the `CC="zig cc -target ..."` escape hatch
  mentioned as unvalidated future work, not a promise).
- Sweep `docs/limitations.md` and doctor messages for stale macOS/Linux
  claims; note the race-detector unavailability applies to Windows purego
  runs too.

## Done When

- No doc or generated message claims purego is macOS/Linux-only; the
  cross-compile recipe is verifiable by copy-paste; `planr overview` shows
  the plan done.
