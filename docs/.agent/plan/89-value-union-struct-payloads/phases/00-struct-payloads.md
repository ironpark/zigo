---
completed_at: "2026-09-02T23:13:36Z"
perf_phase: false
status: done
---
> DONE-WHEN: A union shaped like `sgr.Attribute` (minus its slice-carrying variant, via `.omit_variants`) binds as a value parameter and round-trips in Go tests on both backends.
> NEXT: none

# Struct payloads and omitted variants

## Planned Work

- Reflect packed/extern struct payloads to leaf slots; `.omit_variants`; validation updates and ZIGO006 hint; lowering and emit for parameters on cgo and purego; generator case and example test that passes an RGB-carrying variant end to end.

## Done When

- A union shaped like `sgr.Attribute` (minus its slice-carrying variant, via `.omit_variants`) binds as a value parameter and round-trips in Go tests on both backends.
