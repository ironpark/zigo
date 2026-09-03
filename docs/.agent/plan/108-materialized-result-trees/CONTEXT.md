# SCOPE

- Bindings that do not use `.repr = .materialized` produce identical output.
- The buffer layout is an implementation detail versioned by abi-check; no human-facing stability promise beyond that.

# CONTEXT

## Current implementation and bottlenecks

- Pointer-bearing structs are opaque handles with per-field accessors (plan 87) and child handles (plan 85); tagged unions have `.snapshot` which copies scalar payloads once.
- Lowering owns ABI tables (plans 95/96), so a new lowering kind slots in as a new table entry rather than emitter special cases.

## Target structure and invariants

- One semantic node kind (`materialized`) with a tree description; lowering produces a `MaterializedLayout` table (node records, field kinds, offsets) shared by the Zig walker, the Go decoder and abi-diff.
- Every materialized return is exactly one native call plus one release on both backends.
