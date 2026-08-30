# SCOPE

Modify semantic IR, reflection, validation, ABI/emission helpers, tests, docs, and add one focused example. Preserve existing generated APIs and continue diagnosing unregistered/direct tagged-union values.

# CONTEXT

## Current implementation and bottlenecks

Reflection records only the tagged-union name, validation rejects every such declaration as ZIGO006, and emitters know only ordinary semantic functions. Consequently users must hand-write an opaque facade and accessors.

## Target structure and invariants

The semantic type declaration is the single source of variant names, tag values, and payload nodes. Tagged unions remain handle-like everywhere else. Generated accessors validate the active tag before reading payload memory and return `false` without writing output on mismatch. Generated names participate in collision validation and ABI diff through their type definition.
