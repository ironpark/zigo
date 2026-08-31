---
depends_on:
- "51-sealed-union-variants#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: All ten examples' Go tests pass (cgo and purego); `gofmt -l` and `go vet`
> NEXT: none

# Regenerate examples and add type-switch coverage

## Planned Work

- Regenerate all ten examples (cgo and purego) so every tree reflects the
  final generator.
- Add hand-written tests in example 10 driving every `Value` and `Signal`
  variant through a type switch, including the child-handle variant's
  parent-lifetime behavior (variant's `*ChildRef` dies with its parent) and
  slice-payload defensive copying.
- Document the new surface briefly where the repo documents generated API
  (README or docs section covering tagged unions), if such a section exists.

## Done When

- All ten examples' Go tests pass (cgo and purego); `gofmt -l` and `go vet`
  are clean on regenerated trees.
- The new example-10 tests exercise every variant of both unions via type
  switches; `planr overview` shows the plan done.
