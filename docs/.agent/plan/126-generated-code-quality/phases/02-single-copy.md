---
perf_phase: true
status: in-progress
---
> DONE-WHEN: `zig build test` passes; 07, 08, 11 and 12 pass `go test` on both backends.
> NEXT: none

# Single-copy strings and struct slices

## Planned Work

- Raw string returns and inputs as `string` on cgo and purego; public layer
  drops its conversions (including optional strings).
- Raw struct-slice returns as one `copy`; layout guards for every mirror.
- Regenerate cases and examples; document in `generated-abi.md`,
  `bindings-buffers.md`, CHANGELOG.

## Done When

- `zig build test` passes; 07, 08, 11 and 12 pass `go test` on both backends.
