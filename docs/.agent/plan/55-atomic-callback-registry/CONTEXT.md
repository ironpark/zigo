# SCOPE

Files expected to change: `src/gen/emit.zig` (purego registry block around
the `callbackEntry` emission, unified handle template losing the `once`
field, Close body), golden fixtures (cgo goldens change only for the `once`
removal; purego goldens for both changes), regenerated `examples/*/go*`
trees, and lifecycle/callback tests. No exported names or signatures change;
`ActiveCallbackHandleCount` behavior is unchanged.

# CONTEXT

## Current implementation and bottlenecks

Purego registry (per generated `internal/raw` package):

- `callbackRegistryMu sync.Mutex` guards `map[uintptr]*callbackEntry`.
- `callbackEntry` carries `mu sync.Mutex`, `cond`, `value any`, `closing
  bool`, `active int` — Delete sets `closing`, removes the map entry, and
  waits on the cond until `active` drains; acquire increments `active` under
  the entry mutex; release decrements and broadcasts when a closing entry
  drains.
- `acquireCallback` (every invocation): global lock → map lookup → entry
  lock → closing check → active++ → unlock both.
- Token allocation already uses `nextCallbackToken atomic.Uint64` with a
  zero-skip; `activeCallbackHandles` is already `atomic.Int64`.

Handle template (post plan 53/54): `ptr`, `once sync.Once`,
`mu sync.RWMutex`, `cleanup runtime.Cleanup`, optional `callbackHandles`.
`Close` runs `once.Do` → write-lock → `cleanup.Stop()` → release → nil
fields. The write lock plus the `ptr != nil` check already make the body
idempotent; `once` adds only a redundant fast path.

## Target structure and invariants

- Registry: `var callbackRegistry sync.Map // uintptr -> *callbackEntry`.
  `NewCallbackHandle` stores; `DeleteCallbackHandle` uses `LoadAndDelete`
  (making the unknown-token no-op natural) then performs the existing
  closing/drain protocol on the entry; `acquireCallback` uses `Load` then
  the per-entry mutex exactly as today. No global mutex remains.
- Delete-vs-acquire race stays correct through the existing `closing` flag:
  an acquire that Loads an entry concurrently being deleted either wins
  `active++` before `closing` is observed (Delete then waits for it) or
  observes `closing` and reports the token as gone. State this invariant in
  a comment in the emitted code.
- Close: `mu.Lock(); defer mu.Unlock(); if ptr == nil { return nil }` →
  `cleanup.Stop()` → release → nil fields. No `once` field. Concurrent and
  repeated Close calls remain safe; nil-receiver Close remains a no-op.
- cgo and purego emission stay in lockstep where they share the handle
  template; the registry change is purego-only.
