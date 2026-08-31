# GOALS

## Problem and the end result from the user's point of view

The generated Go bindings work but read as machine output, and their riskiest
deviation from Go convention is the naming of failure modes: the plain method
name (`Tag()`, `zigoMustPointer`-backed methods) panics while the safe variant
is hidden behind a `Try` prefix. Go convention is the opposite (`X() (T, error)`
plus `MustX()` that panics). After this plan, a Go user calling the most natural
name gets an error return, the generated files are roughly half their current
size for tagged unions (handle/ref dedup), enum constants sit in idiomatic
`const` blocks, handles satisfy `io.Closer`, and every example ships bindings
produced by the current generator.

## Measurable goals

- No exported generated method panics unless its name starts with `Must`.
- `Value`/`ValueRef`-style pairs share one projection implementation; the
  tagged-union type file for example 10 shrinks by at least 30%.
- Every enum is one `const ( ... )` block; `gofmt`/`go vet` stay clean.
- Every handle type's `Close` has signature `Close() error`.
- All ten examples' generated Go compiles and their tests pass after
  regeneration; no example still carries the old `sync.RWMutex` lifecycle.

## Supported scope and non-goals

In scope: the Go emission layer (`src/gen/emit.zig` and any templates/naming it
uses), regeneration of `examples/*/go` and `examples/*/go-purego`, and updates
to example tests that reference renamed methods. Non-goals: the Zig ABI/export
side, the purego loading policy, doc-comment passthrough from Zig sources, and
the sealed-interface (variant type) representation of tagged unions — the last
is recorded as a possible follow-up plan, not attempted here.

## Reference source / commit / license

Repository-local work on `main` (starting at 777899c); no external sources.
Existing conventions referenced: `regexp.MustCompile` / `template.Must`
naming, `io.Closer`, stringer-style enum blocks.

## Completion criteria for the whole plan

All phases done; `zig build test` (generator tests, including goldens) passes;
all example Go test suites pass; `planr overview` shows this plan complete.
