---
completed_at: "2026-09-05T20:59:54Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test` passes and the docs describe both.
> NEXT: none

# Per-platform appended LDFLAGS and dynamic docs

## Planned Work

- Add the emitter option and rendering, CLI flag and plumbing, build option.
- Extend the `scalar_multi_target` case and unit tests.
- Document `target_ldflags` and the `.cgo_dynamic` rpath recipe; CHANGELOG.

## Done When

- `zig build test` passes and the docs describe both.
