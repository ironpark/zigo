---
depends_on:
- "54-lock-projection-paths#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: New tests pass under `go test -race`; all fourteen trees pass `go test`,
> NEXT: none

# Race coverage and documentation

## Planned Work

- Extend example 10's lifecycle tests: goroutines running projections on the
  owned handle and through a Ref while another goroutine calls Close, under
  `-race`; assert no race, no crash, and `HandleError` after Close. Include
  a Ref-outliving-parent projection case.
- Regenerate all ten examples (cgo and purego); run the full sweep.
- Remove the unlocked-projection limitation from `docs/limitations.md` and
  update `docs/bindings.md` to state the total guarantee and the
  parameters-stay-unlocked caveat.

## Done When

- New tests pass under `go test -race`; all fourteen trees pass `go test`,
  `gofmt -l`, `go vet`; grep finds no unlocked shared projection
  implementation and no stale limitation text.
- `planr overview` shows the plan done.
