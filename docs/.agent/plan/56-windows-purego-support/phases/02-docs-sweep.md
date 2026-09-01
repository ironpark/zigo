---
depends_on:
- "56-windows-purego-support#0"
perf_phase: false
status: in-progress
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

## Notes

- Docs in this repo are Korean, so `docs/bindings.md` in the planned work is
  really `docs/purego.md` (loader and packaging) plus `docs/generated-code.md`
  (generated file list and library names). Both were updated, along with
  `README.md`, `docs/limitations.md`, and `docs/development.md`.
- The cross-compile section says what is actually true rather than what the
  plan hoped: the Go side cross-compiles (`GOOS=windows CGO_ENABLED=0 go build
  ./...`, no C toolchain, verified on the dev host), while the Zig artifact
  does not, because generation executes a reflector built for the requested
  target. `CC="zig cc -target ..."` is named as unvalidated future work only.
- `docs/development.md` now records that `inspect_shared_library.sh` and the
  smoke loader are POSIX-only, which is why the Windows CI job skips them.
