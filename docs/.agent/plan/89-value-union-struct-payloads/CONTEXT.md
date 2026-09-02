# SCOPE

- Layout: keep the plan-81 approach (tag then per-variant slots in declaration order). Struct payloads add one slot per leaf scalar; packed structs add one integer slot. Go constructors take the Go value struct (generate a value struct type per payload struct if not registered; reuse the registered `.value` mirror when present).
- Returns: `zg_<fn>(out: *ValueSnapshot) status` where the snapshot is an `extern struct` with tag and the same slots; Go decodes to the same sealed variant types used for parameters.

# CONTEXT

## Current implementation and bottlenecks

- `validate.zig:166-237` rejects non-scalar payloads with ZIGO006 and forbids value returns.
- `lower.zig` `isValueOnlyTaggedUnion` decides value-only unions; the slot builder assumes scalar payloads.

## Target structure and invariants

- Every accepted payload has a fixed, comptime-known slot list; the shim reconstructs the exact Zig union value; omitted variants never appear in generated code.
