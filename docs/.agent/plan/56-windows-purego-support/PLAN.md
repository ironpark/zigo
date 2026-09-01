---
completed_at: "2026-09-01T15:24:48Z"
description: "Windows support via the purego backend: build-tagged LoadLibrary loader, .dll naming, platform gate + doctor, Windows CI, and a zig-cc cross-compile story"
plan_status: done
registered_at: "2026-09-01T14:47:54Z"
---
> NEXT: Emit the build-tagged Windows loader and open the platform gate. ([Phase 0](phases/00-windows-loader.md))

# Phases

- [x] [Phase 00: Windows loader emission and platform gate](phases/00-windows-loader.md)
- [x] [Phase 01: Windows CI job with native and cross-built DLLs](phases/01-windows-ci.md)
- [x] [Phase 02: Cross-compile documentation and platform docs sweep](phases/02-docs-sweep.md)
- [x] [Phase 03: Windows-compilable Zig tooling](phases/03-windows-compilable-zig-tooling.md)

# Shared Verification

- `zig build test` after every phase (goldens for both loader tag variants,
  doctor unit tests, build_options tests).
- Phase 0: `GOOS=windows CGO_ENABLED=0 go vet ./... && go build ./...` per
  purego example on the dev host; full POSIX purego suites.
- Phase 1: green `windows-latest` CI job covering native and cross-built
  DLLs; Ubuntu jobs unchanged and green.
- Grep checks: `windows` present in every regenerated `DefaultLibraryName`;
  no "require macOS or Linux" text left in doctor or docs.

# Decisions That Constrain Ordering

Phase 0 makes Windows work; phase 1 proves it continuously in CI and
depends on it. Phase 2 only documents phase 0's result and can run in
parallel with phase 1; both must finish to complete the plan.

# Next Implementation Target

Emit the build-tagged Windows loader and open the platform gate.
