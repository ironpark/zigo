# SCOPE

- Atomicity guarantee is per field access only (`seq_cst` load/store); a struct snapshot is not atomic as a whole, and the docs say so.

# CONTEXT

## Current implementation and bottlenecks

- `typeNode` struct branch appends an unregistered value struct for any struct type; `reflectFlattenedFields` and the `.fields` leaf check only accept bool/int/float/enum.
- `writeFieldAccess` in `emit.zig` reads `self.<path>` directly and assigns through `writeShimInboundValue`.

## Target structure and invariants

- One predicate `atomicScalar(T) ?type` in reflection decides atomic-ness; every consumer of scalar leaves calls it.
