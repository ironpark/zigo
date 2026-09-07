---
depends_on:
- "143-composable-declaration-dsl#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Lifecycle modifiers preserve unrelated metadata and produce the same typed schema as literals.
> NEXT: none

# Lifecycle ergonomics and documentation

## Planned Work

- Add constructor, destructor, and child-of-receiver fluent modifiers without mirroring every `Function` field.
- Document exact selectors, path projection, generic collection, type batches, and lifecycle composition using a complex-binding-oriented example.
- Update the changelog and run formatting, focused tests, and the complete repository test suite.

## Done When

- Lifecycle modifiers preserve unrelated metadata and produce the same typed schema as literals.
- Documentation states the ABI-stability difference between `names` and prefix selection.
- Formatting and the full test suite pass.
