---
completed_at: "2026-08-31T07:10:42Z"
depends_on:
- "34-generated-go-idioms#0"
perf_phase: false
status: done
---
> DONE-WHEN: Generated signatures use camelCase parameters, keyword-named Zig parameters compile, one receiver
> NEXT: none

# Go Naming for the Public API

## Planned Work

- Convert public parameter names to camelCase, and escape names that collide with a Go keyword or
  with another parameter in the same signature, in both the public and raw layers.
- Name a callback type after its function without repeating the word Callback, and keep one
  receiver name per type across every generated file.
- Cover a binding whose Zig parameters are named `type`, `range` and `func` with a generator case
  that compiles.

## Done When

- Generated signatures use camelCase parameters, keyword-named Zig parameters compile, one receiver
  name is used per type, and every example passes `go vet` and its tests.
