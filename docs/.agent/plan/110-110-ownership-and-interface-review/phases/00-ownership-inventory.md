---
perf_phase: false
status: planned
---
> DONE-WHEN: The table is in `docs/.agent/design/10-ownership-model.md` and every row
> NEXT: none

# Inventory ownership paths

## Planned Work

- Table every shape that transfers or borrows native memory: handle
  constructor/destructor pairs (`boxed`, `child_of_receiver`), borrowed handle
  returns, caller-owned `[]T`/`![]T`/`?[]T` with `.release`, C-string returns,
  narrow-int slices (temporary storage), materialized return and out buffers,
  retained callbacks and stream adapters.
- For each row record: the semantic fields that select it, the `AbiFn`
  fields lowering sets, the emit function per backend, what happens on the
  error/absent path, and whether Go ever holds native memory after the call.
- Note where two rows do the same work with different code (the release
  candidate lookup, the copy-then-release sequence in cgo versus purego).

## Done When

- The table is in `docs/.agent/design/10-ownership-model.md` and every row
  cites a golden case under `tests/generator_cases` that exercises it.
