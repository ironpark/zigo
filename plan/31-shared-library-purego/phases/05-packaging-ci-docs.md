---
depends_on:
- "31-shared-library-purego#4"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Fresh-user instructions reproduce both backends, all generated artifacts and golden fixtures are
> NEXT: none

# Packaging, CI, and User Documentation

## Planned Work

- Document native shared-library production, per-platform artifact distribution, explicit/env/default
  loading, purego dependency pinning, security considerations, backend selection, and why Zig artifacts
  still require a per-target CI matrix.
- Extend standard steps with discoverable shared/purego validation, and make doctor check the selected
  backend: C compiler/cgo only for cgo; shared artifact, purego module, target support, and runtime load
  probe for purego.
- Add macOS/Linux amd64/arm64 CI jobs for shared artifact inspection and `CGO_ENABLED=0` Go tests;
  retain the existing static/cgo stale, ABI, and Go matrix.

## Done When

- Fresh-user instructions reproduce both backends, all generated artifacts and golden fixtures are
  current, supported CI targets pass the full matrix, unsupported targets fail with actionable
  diagnostics, and limitations accurately describe purego beta/version/callback constraints.
