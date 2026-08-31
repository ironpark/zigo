# GOALS

## Problem and the end result from the user's point of view

Reading a Zig tagged union from Go today means probing: call `Tag()`, then the
matching `AsX() (T, bool, error)` projection, or walk a getter-style snapshot.
Go's idiomatic representation of a sum type is a sealed interface with one
concrete type per variant (as in `go/ast` nodes or protobuf oneof), consumed
with a single type switch:

    v, err := value.Variant()
    switch p := v.(type) {
    case tagged_union.ValueInteger: use(p.Value)
    case tagged_union.ValueNone:    ...
    }

After this plan, every generated tagged union additionally exposes a sealed
payload interface, per-variant concrete types, and a `Variant()` accessor on
both the owned handle and the borrowed ref. The existing `Tag`/`As*`/
`Snapshot` surface stays; this is additive.

## Measurable goals

- Every tagged union emits `<Union>Variant` (sealed interface with an
  unexported marker method) and one exported concrete type per Zig variant,
  including payloadless variants as empty structs.
- `Variant() (<Union>Variant, error)` and `MustVariant() <Union>Variant`
  exist on the handle and ref types, delegating to one shared implementation
  per the plan-50 dedup pattern.
- Unions whose payloads are all scalar (snapshot-eligible, e.g. `Signal` in
  example 10) materialize the variant from the existing single-call snapshot
  read; no per-variant extra native calls.
- Example 10 gains a test that drives every variant of both `Value` and
  `Signal` through a type switch; all example tests, `gofmt -l`, `go vet`,
  and `zig build test` pass.

## Supported scope and non-goals

In scope: Go emission (`src/gen/emit.zig`), golden fixtures, regeneration of
the examples containing tagged unions (at minimum example 10; regenerate all
ten for consistency), and new example tests. Non-goals: removing or renaming
the existing `Tag`/`As*`/`Must*`/`Snapshot` surface, constructing or setting
union values through variant types (read-only representation), changes to the
Zig ABI/export layer, and the callback `sync.RWMutex` lifecycle question noted
in plan 50's NEXT.

## Reference source / commit / license

Repository-local work on `main` (starting at ef4fb30, plan 50 complete).
Idiom references: `go/ast.Node` sealed hierarchy, protobuf-go oneof wrapper
types.

## Completion criteria for the whole plan

All phases done; `zig build test` and all example Go test suites pass;
`planr overview` shows this plan complete.
