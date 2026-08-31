---
completed_at: "2026-08-31T05:26:50Z"
perf_phase: false
status: done
---
> DONE-WHEN: Generated static cgo files name the archive, dynamic and overridden files are unchanged, and
> NEXT: none

# Explicit Static Archive Link

## Planned Work

- Carry the link mode from `addGoBindings` through the generate CLI into the generator and emitter
  options, defaulting to static.
- Emit `{library_dir}/lib{stem}.a` for static cgo links and keep `-L{dir} -l{stem}` for dynamic
  links, leaving overrides, system libraries, and framework flags unchanged.
- Cover both forms and the override precedence with emitter or generator unit tests, and regenerate
  every committed cgo raw file and golden fixture.

## Done When

- Generated static cgo files name the archive, dynamic and overridden files are unchanged, and
  `zig build test` plus every example's `test go-check abi-check` and `go test ./...` pass.
