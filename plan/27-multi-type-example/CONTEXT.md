# SCOPE

Create the source, binding declaration, build graph, generated Go/IR artifacts, documentation, tests, and CI entry for one focused multi-type example.

# CONTEXT

## Current implementation and bottlenecks

Existing examples expose multiple enums or broad APIs but do not isolate two opaque declarations with a receiver method that accepts the other opaque declaration.

## Target structure and invariants

Both types are declared once as opaque. `Accumulator` owns `absorb`; `Counter` is a borrowed parameter. Each type has an independent create/deinit mapping and all live allocations return to zero.
