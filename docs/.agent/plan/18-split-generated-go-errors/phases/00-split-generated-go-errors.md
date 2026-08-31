---
completed_at: "2026-08-30T05:21:54Z"
perf_phase: false
status: done
---
> DONE-WHEN: `pkgname_errors_gen.go` contains the complete unchanged public error API while the main file no longer does; all planned verification passes, generated trees are clean, implementation is committed, and the plan phase can be marked done.
> NEXT: none

# Split Generated Go Errors

## Planned Work

- Add a dedicated public-error emitter and package-based path, remove error rendering/import requirements from the main emitter, and extend generator tests for separated and colocated raw packages.
- Thread the third Go output through formatting and source update steps, refresh golden fixtures and all eight examples, and document the generated layout.
- Run focused, repository-wide, cross-target, regeneration, ABI, and Go integration verification.

## Done When

- `pkgname_errors_gen.go` contains the complete unchanged public error API while the main file no longer does; all planned verification passes, generated trees are clean, implementation is committed, and the plan phase can be marked done.
