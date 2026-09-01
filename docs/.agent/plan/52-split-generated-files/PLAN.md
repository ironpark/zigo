---
description: "Split the monolithic <pkg>_type_gen.go into concern-based files: enums, handles, runtime, and one file per tagged union"
plan_status: in-progress
registered_at: "2026-09-01T10:37:00Z"
---
> NEXT: Build per-file writer plumbing and split enums, handles, and runtime into their own files. ([Phase 0](phases/00-static-split.md))

# Phases

- [x] [Phase 00: Per-file writer plumbing and static split (enums, handles, runtime)](phases/00-static-split.md)
- [x] [Phase 01: Per-union files](phases/01-per-union-files.md)
- [ ] [Phase 02: Regenerate all examples and update docs](phases/02-regen-and-docs.md)

# Shared Verification

- `zig build test` after every phase (emit/naming unit tests, goldens for cgo
  and purego, generator file-presence tests).
- Per-phase example runs as listed in each Done When; full fourteen-tree
  sweep (`go test`, `gofmt -l`, `go vet`) in phase 2.
- Content-preservation check in phase 1: concatenate the split files per
  package and diff declarations against the pre-split emission.
- Grep checks: no retired file names under `examples/` or in docs after
  phase 2.

# Decisions That Constrain Ordering

Phase 0 builds the multi-writer plumbing on the easy, fixed-content splits.
Phase 1 uses that plumbing for the per-union files, which need the naming
work. Phase 2 is the repo-wide sweep and depends on the final layout.

# Next Implementation Target

Build per-file writer plumbing and split enums, handles, and runtime into their own files.
