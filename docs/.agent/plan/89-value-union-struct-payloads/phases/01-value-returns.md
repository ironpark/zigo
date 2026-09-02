---
completed_at: "2026-09-02T23:26:44Z"
depends_on:
- "89-value-union-struct-payloads#0"
perf_phase: false
status: done
---
> DONE-WHEN: A function returning a value union works on both backends; verification loop green.
> NEXT: none

# Value union returns

## Planned Work

- Out-parameter snapshot return for value unions; Go decoding into the variant types; error for omitted tags; docs and CHANGELOG; example test returning a value union.

## Done When

- A function returning a value union works on both backends; verification loop green.
