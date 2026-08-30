---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zig build test --summary all` passes.
> NEXT: none

# Configurable raw package placement

## Planned Work

- Add and validate the raw-package placement option in the Zig build API and carry its resolved path, package name, and colocation state through the generator CLI.
- Make emitter paths, package declarations, imports, and low-level references mode-aware while preserving callback C symbols and the default generated output.
- Configure examples for custom-path and colocated modes, refresh generated Go sources and snapshots, and add focused regression coverage.
- Document all modes and the one-time cleanup required when switching an existing output tree.

## Done When

- `zig build test --summary all` passes.
- All example generation, `go-check`, `abi-check`, and `go test ./...` commands pass.
- Generated paths and symbols demonstrate default, custom-path, and colocated modes, and `git diff --check` is clean.
