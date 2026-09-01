---
depends_on:
- "52-split-generated-files#1"
perf_phase: false
status: planned
---
> DONE-WHEN: No `_type_gen.go` or `_helpers_gen.go` remains under `examples/`; all ten
> NEXT: none

# Regenerate all examples and update docs

## Planned Work

- Regenerate all ten examples, cgo and purego; confirm sync/prune removes the
  retired `_type_gen.go`/`_helpers_gen.go` files from every tree.
- Update any docs that name generated files (`docs/bindings.md`,
  `docs/examples.md`, READMEs) to the new layout.
- Grep the repo for hard-coded references to retired file names (tests,
  scripts, docs) and update them.

## Done When

- No `_type_gen.go` or `_helpers_gen.go` remains under `examples/`; all ten
  examples' Go tests pass (cgo and purego), `gofmt -l` and `go vet` clean.
- Docs reflect the new file set; `planr overview` shows the plan done.
