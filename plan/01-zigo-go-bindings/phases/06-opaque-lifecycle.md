---
depends_on:
- "01-zigo-go-bindings#5"
perf_phase: false
status: planned
---
> DONE-WHEN: A create-and-destroy loop in the Go tests ends with the counting allocator reporting
> NEXT: none

# Opaque handles and lifetimes

## Planned Work

- Accept `.types` entries with `.repr = .@"opaque"` and reject by-value use of a
  non-extern, non-packed struct as ZIGO003.
- Pair constructors with destructors by name — init, create, new, open against deinit,
  destroy, close — and record the pairing in the IR.
- Lower methods: set the receiver and drop the leading `self` parameter.
- Emit the Go handle type with `New*() (*T, error)` and an idempotent `Close()` guarded
  by `sync.Once`; deliberately do not attach a finalizer.
- Emit the borrowed `TRef` wrapper holding a parent reference so the owner cannot be
  collected early.
- Add `examples/03-opaque` with a counting allocator that exposes its live-byte count.

## Done When

- A create-and-destroy loop in the Go tests ends with the counting allocator reporting
  zero live bytes.
- Calling `Close()` twice is safe.
- A by-value non-extern struct produces ZIGO003 with the `extern struct` hint, and no
  files are written.
