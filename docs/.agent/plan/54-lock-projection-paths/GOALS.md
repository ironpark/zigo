# GOALS

## Problem and the end result from the user's point of view

Plan 53 unified the handle lifecycle, but tagged-union projections
(`Tag`/`As*`/`Snapshot`/`Variant`) and every borrowed-Ref method still run
without the read lock: their shared implementations reach handles through the
`zigoHandle` interface, which only exposes `zigoPointer()`, so `mu` is
invisible at those call sites. A Close racing an in-flight projection is
still a use-after-free — documented today in `docs/limitations.md`. After
this plan the serialization guarantee is total: every generated native call
through an owned handle or a borrowed ref holds the owner's read lock, and
the limitations entry is removed.

## Measurable goals

- `zigoHandle` gains a locker accessor; owned handles return `&h.mu`, Refs
  delegate to their parent's locker, nil receivers return nil.
- Every shared projection/snapshot/variant implementation acquires the read
  lock in its prologue; public wrappers and `Must*` delegations are
  unchanged.
- A `-race` test drives concurrent projections (owned and via Ref) against
  Close without races; post-Close projections return `HandleError`.
- The unlocked-projection entries in `docs/limitations.md` and
  `docs/bindings.md` are removed/updated.
- All ten examples (cgo and purego) pass `go test -race`, `gofmt -l`,
  `go vet`; `zig build test` passes.

## Supported scope and non-goals

In scope: the `zigoHandle` interface and its implementations in
`src/gen/emit.zig` handle/ref emission, the lock prologue in shared
projection/snapshot/variant implementations, goldens, regeneration, tests,
and docs. Non-goals: locking handle-typed parameters (receiver/parent-chain
locking only — multi-lock ordering is deliberately avoided and stays
documented), changes to the public API surface, `runtime.KeepAlive` removal,
and the callback registry.

## Reference source / commit / license

Repository-local work on `main` (starting after plan 53, commit 1424633).
The gap is recorded in `docs/limitations.md` by plan 53's phase 2.

## Completion criteria for the whole plan

All phases done; `zig build test` and all fourteen example Go trees green
under `-race`; `planr overview` shows the plan complete.
