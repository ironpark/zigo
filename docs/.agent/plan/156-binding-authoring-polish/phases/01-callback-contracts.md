---
depends_on:
- "156-binding-authoring-polish#0"
perf_phase: false
status: planned
---
> DONE-WHEN: Callback conventions match function indices and existing callback behavior is preserved in tests/examples.
> NEXT: none

# Sparse callback contracts

## Planned Work

- Share callback native-to-logical layout between normalization and reflection.
- Normalize sparse original-index callback metadata; reject duplicate, out-of-range, userdata and folded-length annotations.
- Rename public callback failure option to on_failure and migrate consumers.

## Done When

- Callback conventions match function indices and existing callback behavior is preserved in tests/examples.
