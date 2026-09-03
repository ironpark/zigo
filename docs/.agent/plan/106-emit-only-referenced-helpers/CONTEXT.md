# SCOPE

- Public API of generated packages does not change.

# CONTEXT

## Current implementation and bottlenecks

- Helper emission is keyed on type presence (has opaque, has callbacks, has castable struct) rather than on actual references.

## Target structure and invariants

- Use-site predicates live next to the emitters that produce the references.
