---
depends_on:
- "110-110-ownership-and-interface-review#0"
perf_phase: false
status: planned
---
> DONE-WHEN: The design document has the mapping table, the feature assessment, the
> NEXT: none

# Ownership design and recommendation

## Planned Work

- Propose the IR record (working name `Ownership { holder, transfer, release }`)
  and show how each inventory row maps onto it; call out rows that cannot
  map without changing the generated Go.
- Evaluate the two motivating features against the record: automatic
  `runtime.AddCleanup` for caller-owned non-handle results, and an arena
  scope API (`WithArena(func(a *Arena))`) that batches releases. State what
  each needs from the record and what it costs in generated code and docs.
- Assess `semantic.json` compatibility: whether the record can be derived
  from today's fields (no IR version bump) or needs new fields, and what
  `abi-diff` must learn.
- Recommend: adopt with phased migration, adopt for new shapes only, or
  decline. Give an estimated phase list for the accepted option.

## Done When

- The design document has the mapping table, the feature assessment, the
  compatibility section and a recommendation.
