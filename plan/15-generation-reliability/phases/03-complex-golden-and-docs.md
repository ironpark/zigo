---
depends_on:
- "15-generation-reliability#2"
perf_phase: false
status: planned
---
> DONE-WHEN: The complex fixture detects changes in all generated artifact forms, docs match
> NEXT: none

# Complex golden coverage and documentation

## Planned Work

- Add a full-tree golden fixture combining the major lowering and emission paths,
  document atomicity/lock/enrichment guarantees, and run repository-wide Zig,
  cross-target, example, and Go verification.

## Done When

- The complex fixture detects changes in all generated artifact forms, docs match
  implemented guarantees, and every repository verification command passes.
