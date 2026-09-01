# SCOPE

Files expected to change: `src/gen/emit.zig` (runtime block emitting
`zigoHandle` and helpers; handle/ref struct emission adding the locker
method; shared implementation prologues for union projections, snapshots,
and variant builders), golden fixtures (cgo and purego), regenerated
`examples/*/go*` trees, lifecycle tests in example 10 (and one callback
example if its unions warrant it), `docs/limitations.md`,
`docs/bindings.md`. No exported name or signature changes.

# CONTEXT

## Current implementation and bottlenecks

- Runtime (`<pkg>_runtime_gen.go`): `zigoHandle` is
  `interface { zigoPointer() unsafe.Pointer }`; `zigoCheckedPointer`
  resolves and checks the pointer.
- Union files: shared implementations like
  `zigoValueTag(receiver zigoHandle)` do `defer runtime.KeepAlive` +
  `zigoCheckedPointer` + raw call — no lock. Public handle and Ref methods
  are one-line delegations (plan 51), so only the shared implementations
  need the prologue.
- Handles (post plan 53) all carry `mu sync.RWMutex`; Ref types carry
  `ptr` + `parent zigoHandle` and validate through the parent chain in
  `zigoPointer()`. Parent chains can be multi-level; delegation must
  recurse.
- Operation methods in `<pkg>_gen.go` already read-lock the receiver
  directly; they are not part of this gap.

## Target structure and invariants

- `zigoHandle` becomes `interface { zigoPointer() unsafe.Pointer;
  zigoLocker() *sync.RWMutex }`. Owned handle: nil receiver → nil, else
  `&h.mu`. Ref: nil receiver or nil parent → nil, else
  `parent.zigoLocker()`.
- One shared prologue helper (e.g. `zigoReadLock(receiver) func()` or an
  inline `if mu := receiver.zigoLocker(); mu != nil { mu.RLock(); defer
  mu.RUnlock() }`) emitted at the top of every shared
  projection/snapshot/variant implementation, before the pointer check, so
  the pointer cannot be invalidated between check and native call.
- No nested lock acquisition: shared implementations never call each other
  while holding the lock — the variant builder must release between its tag
  read and payload projection, or acquire once around a single composed
  body; either is acceptable but must be deadlock-free and stated in the
  golden.
- Close's write lock now serializes against projections and Ref reads too;
  Close-during-projection blocks until the projection finishes, and
  projections after Close return `HandleError`.
- Parameters stay unlocked (documented); cgo and purego in lockstep.
