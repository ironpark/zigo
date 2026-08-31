---
completed_at: "2026-08-31T05:59:04Z"
perf_phase: false
status: done
---
> DONE-WHEN: Validation and CLI parsing are unit tested, `go-report` prints the effective policy, and every
> NEXT: none

# Loading Policy Option and Plumbing

## Planned Work

- Add the `LibraryLoading` option, its defaults, and its validation rules (purego only, exported
  API implies nothing, unexported API requires automatic, well-formed environment names and
  candidate paths) to `src/build_options.zig`, and apply them in `addGoBindings`.
- Thread the policy through the generate CLI as repeatable arguments into generator and emitter
  options, and report it in `go-report`.
- Keep the generated output unchanged for the default value.

## Done When

- Validation and CLI parsing are unit tested, `go-report` prints the effective policy, and every
  example regenerates with no diff.
