---
perf_phase: false
planr_base: sha256:4ab04872ad8f09e88596787d418c9b55cbcf36b8b07859d1439b7b7f5580c184
planr_edit: "align-ci-go-version#0"
planr_phase: 0
planr_slug: initial-work
planr_target: plan/37-align-ci-go-version/phases/00-initial-work.md
status: in-progress
---
> DONE-WHEN: The affected `go.mod` files declare Go 1.24, no example requires a newer version, tests pass, and the scoped fix is committed.
> NEXT: none

# Initial Work

## Planned Work

- Lower the two incompatible module directives to Go 1.24, verify all example module directives, and run the affected Go tests.

## Done When

- The affected `go.mod` files declare Go 1.24, no example requires a newer version, tests pass, and the scoped fix is committed.
