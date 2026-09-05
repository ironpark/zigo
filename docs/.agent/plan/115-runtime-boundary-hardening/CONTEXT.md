# SCOPE

Source generators, generated fixtures/examples, focused regressions, CI and changelog.

# CONTEXT

## Current implementation and bottlenecks

Readers discard errors accompanying data and conflate empty reads with EOF. Materialized builders panic without cleanup and decoders allocate before validating counts.

## Target structure and invariants

Reader contracts agree across backends. Error-returning serialization cleans up before panic translation. Decoders validate storage before allocating.
