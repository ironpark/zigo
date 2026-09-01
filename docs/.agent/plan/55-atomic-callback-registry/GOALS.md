# GOALS

## Problem and the end result from the user's point of view

In the purego backend, every native→Go callback invocation takes a global
mutex: `acquireCallback` locks `callbackRegistryMu`, looks the token up in a
plain map, then locks the per-entry mutex. Concurrent callbacks from
different goroutines/threads all contend on that one global lock. The cgo
backend has no such bottleneck — it uses `cgo.Handle`, which is a `sync.Map`
internally. The workload is exactly `sync.Map`'s sweet spot: one insert per
handle, rare deletes, a lookup per invocation. After this plan the purego
registry lookup is lock-free and behaviorally symmetric with cgo, while the
per-entry drain-on-delete guarantee (Delete waits for in-flight invocations)
is unchanged. As a small companion cleanup, the generated `Close` drops its
`sync.Once` field, whose idempotency is already provided by the write lock
plus the nil-pointer check.

## Measurable goals

- `acquireCallback` performs no global mutex acquisition: the registry is a
  `sync.Map` (or equivalent atomic structure) and the global
  `callbackRegistryMu` is gone.
- `NewCallbackHandle` / `DeleteCallbackHandle` semantics are unchanged:
  tokens stay unique and non-zero, Delete blocks until in-flight invocations
  drain, double-Delete and Delete-of-unknown-token stay safe no-ops.
- Generated handle structs no longer carry `once sync.Once`; `Close` stays
  idempotent and race-safe (existing `-race` lifecycle tests still pass,
  extended with a concurrent double-Close case).
- A `-race` purego test exercises concurrent callback invocations racing
  `DeleteCallbackHandle` and concurrent handle creation/deletion.
- All ten examples (cgo and purego) pass `go test` (`-race` on cgo trees),
  `gofmt -l`, `go vet`; `zig build test` passes.

## Supported scope and non-goals

In scope: the purego callback registry emission in `src/gen/emit.zig`
(`NewCallbackHandle`, `DeleteCallbackHandle`, `acquireCallback`,
`releaseCallback`, registry globals), the handle-struct `once` removal in
the unified lifecycle template, goldens, regeneration, and tests. Non-goals:
the cgo callback path (`cgo.Handle`, already lock-free), the per-entry
`mu`/`cond` drain mechanism (waiting requires blocking; it stays), the
handle `RWMutex` (load-bearing for the Close-serialization guarantee, per
plan 53/54 — explicitly do not touch), and any public API change.

## Reference source / commit / license

Repository-local work on `main` (starting after plan 54, commit d21c57a).
References: `runtime/cgo.Handle` implementation (sync.Map-based) for the
target semantics; current purego registry in
`examples/04-callback/go-purego/internal/raw/raw_gen.go:66-146`.

## Completion criteria for the whole plan

All phases done; `zig build test` and all fourteen example Go trees green;
`planr overview` shows the plan complete.
