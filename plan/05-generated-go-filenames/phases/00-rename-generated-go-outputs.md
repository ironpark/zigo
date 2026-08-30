---
completed_at: "2026-08-30T01:57:07Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test --summary all` passes with path assertions for `raw_gen.go` and package-specific public files.
> NEXT: none

# Rename generated Go outputs

## Planned Work

- Change raw and public emitter paths and the matching `UpdateSourceFiles` copy destinations.
- Update generator tests to assert package-derived `_gen.go` paths and preserve validation no-write guarantees.
- Regenerate all five examples, remove legacy filenames, and update documentation.
- Verify Zig tests, example generation, stale/ABI checks, Go tests, filename inventory, and diff cleanliness.

## Done When

- `zig build test --summary all` passes with path assertions for `raw_gen.go` and package-specific public files.
- Each example passes `zig build go go-check abi-check --summary all` and `go test -count=1 ./...`.
- Every generator-owned example Go file matches `*_gen.go`, with no `generated.go` or `cgo.go` remaining.
- Documentation and checked-in generated artifacts match the new contract and the change is committed.
