---
completed_at: "2026-09-01T19:14:12Z"
description: "Native Windows cgo backend using CC=zig cc: spike the build, fix emission/doctor as needed, prove it in Windows CI without mingw"
plan_status: done
registered_at: "2026-09-01T18:27:05Z"
---
> NEXT: Run the cgo + zig cc build spike against Windows targets from this host. ([Phase 0](phases/00-spike.md))

# Phases

- [x] [Phase 00: Build spike: cgo + zig cc for Windows, from POSIX](phases/00-spike.md)
- [x] [Phase 01: Windows cgo CI job](phases/01-windows-cgo-ci.md)
- [x] [Phase 02: Doctor and docs](phases/02-doctor-and-docs.md)

# Shared Verification

- `zig build test`/`check` (native + windows cross-check) after every
  phase; ten cgo + four purego trees locally.
- Phase 0: the two cross-built Windows test executables exist (or the
  documented blocker); POSIX trees drift-free unless emission
  deliberately changed.
- Phase 1: green CI on all jobs.
- Phase 2: doctor probe unit tests; docs grep.

# Decisions That Constrain Ordering

The spike gates everything: phases 1 and 2 are written for the success
path and must be amended via `planr edit` to match the spike verdict
before starting. Phase 2 depends only on the spike, so it may run
before or parallel to phase 1's CI loop.

# Next Implementation Target

Run the cgo + zig cc build spike against Windows targets from this host.
