---
depends_on:
- "34-generated-go-idioms#1"
perf_phase: false
status: planned
---
> DONE-WHEN: Doc comments read as sentences, unknown enum values and error codes carry their number, no empty
> NEXT: none

# Readable Comments and Diagnostics

## Planned Work

- Join Zig doc text to the Go identifier as one sentence instead of concatenating two capitalized
  words.
- Report the numeric value in an enum `String()` default branch and the unrecognized code in the
  generated error message.
- Stop writing a generated file that has no declarations, treat a previously written empty file as
  obsolete, and give a borrowed reference its concrete handle type instead of `any` plus a per-call
  interface assertion.

## Done When

- Doc comments read as sentences, unknown enum values and error codes carry their number, no empty
  generated file remains, and stale-output detection removes the ones already committed.
