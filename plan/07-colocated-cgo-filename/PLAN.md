---
description: Rename colocated low-level Go output from package_raw_gen.go to package_cgo_gen.go while preserving separate raw package filenames.
plan_status: in-progress
registered_at: "2026-08-30T02:17:11Z"
---
> NEXT: Rename and verify the colocated cgo output file. ([Phase 0](phases/00-rename-colocated-cgo-output.md))

# Phases

- [ ] [Phase 00: Rename colocated cgo output](phases/00-rename-colocated-cgo-output.md)

# Shared Verification

Run `zig build test --summary all`, the 01-scalar `go`, `go-check`, and `abi-check` steps, `go test -count=1 ./...`, a repository filename search, and `git diff --check`.

# Decisions That Constrain Ordering

The path producer and consuming update step change together so generated and source paths cannot diverge.

# Next Implementation Target

Rename and verify the colocated cgo output file.
