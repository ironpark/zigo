# SCOPE

Primary files are `src/gen/generator.zig`, `src/gen/ir/errors_lock.zig`,
`src/reflect/names.zig`, `src/reflect/main.zig`, `tests/generator_cases`, and the
generation/IR documentation. Build wiring changes are included only when needed
to exercise these contracts.

# CONTEXT

## Current implementation and bottlenecks

The generator writes each emitter result immediately, so a later rendering or
allocation error can leave a mixed output tree. The lock parser accepts any IR
version and ignores the serialized reserved map. Enrichment silently swallows
primary/auxiliary read errors and invalid Zig ASTs. Only the scalar golden case
exercises the complete generator tree.

## Target structure and invariants

Generation has a prepare phase that owns every rendered byte and a commit phase
that performs no allocator-dependent work. Lock parsing establishes a valid
canonical state before append-only assignment. Optional auxiliary reflection
sources may be absent, but actual read and parse failures are visible and retain
fallback names. Golden fixtures compare the full directory tree.
