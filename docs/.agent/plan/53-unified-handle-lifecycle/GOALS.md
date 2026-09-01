# GOALS

## Problem and the end result from the user's point of view

The generator currently emits two divergent handle lifecycles, chosen by a
program-level flag. Programs with any callback anywhere give every handle a
`sync.RWMutex` (methods RLock, Close write-locks) but no GC safety net;
programs without callbacks give every handle `runtime.AddCleanup` +
`runtime.KeepAlive` but no Close-vs-in-flight-call serialization. Each scheme
has a real hole the other one plugs: callback-program handles leak native
memory and callback-registry entries if the user forgets Close, and
non-callback handles can hit a use-after-free when Close races an in-flight
method. After this plan there is one lifecycle: every owned handle carries
`once` + `RWMutex` + `AddCleanup`; methods hold the read lock, Close
write-locks, stops the cleanup, deinits, and frees any callback handles; the
GC cleanup does the same for abandoned handles. Callback bookkeeping appears
only on types that actually own callbacks.

## Measurable goals

- One lifecycle template in the emitter; the program-level callback flag no
  longer selects between schemes. `callbackHandles` fields exist only on
  types whose constructors accept callbacks.
- Every owned handle type in every example has: RWMutex serialization in
  methods and Close, `runtime.AddCleanup` registered at construction, and a
  cleanup that releases native memory and callback handles.
- A `-race` test in an example with callbacks (04 or 05) exercises concurrent
  method calls racing Close without data races or use-after-free.
- A test proves abandoned callback-carrying handles are reclaimed: after
  dropping the handle and forcing GC, the callback registry count returns to
  its baseline.
- All ten examples (cgo and purego) pass `go test` (including `-race` where
  the suite runs it), `gofmt -l`, `go vet`; `zig build test` passes.

## Supported scope and non-goals

In scope: handle-lifecycle emission in `src/gen/emit.zig` (struct fields,
constructor, Close, cleanup, per-method locking prologues), the callback
registry interaction needed by cleanup, goldens, regeneration of all
examples, and new lifecycle tests. Non-goals: the callback registry design
itself, borrowed-Ref semantics, the public API surface (no renames), and any
Zig-side change.

## Reference source / commit / license

Repository-local work on `main` (starting after plan 52, commit f2f65d6).
Prior art in-repo: the AddCleanup scheme (example 10's handles pre-plan-52,
now in `*_handles_gen.go` of non-callback examples) and the RWMutex scheme
(example 04's `callback_handles_gen.go`). This item was recorded in plan 50's
NEXT notes.

## Completion criteria for the whole plan

All phases done; `zig build test` and all fourteen example Go trees green;
`planr overview` shows the plan complete.
