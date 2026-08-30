---
completed_at: "2026-08-30T03:36:33Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test --summary all` passes.
> NEXT: none

# Enforce stale checks and normalized artifacts

## Planned Work

- Use the normalized binding stem for the installed Zig library and generated header.
- Reorder CI so stale Go output is checked before generation and gate all generated example changes afterward.
- Add a CamelCase-name example that exercises generation, header installation, library linking, and Go calls.

## Done When

- `zig build test --summary all` passes.
- Every example passes `zig build go-check abi-check --summary all`, `zig build go`, and `go test ./...` in the CI order.
- The repository is clean after regeneration, and the CamelCase example's generated cgo directives match installed artifacts.
