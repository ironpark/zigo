---
depends_on:
- "34-generated-go-idioms#1"
perf_phase: false
planr_base: sha256:43253febdb7f1bcfc0b7bb6d3a68cc36e3730a9639e5035547fed0848283a87a
planr_edit: "generated-go-idioms#2"
planr_phase: 2
planr_slug: comments-and-diagnostics
planr_target: plan/34-generated-go-idioms/phases/02-comments-and-diagnostics.md
status: in-progress
---
> DONE-WHEN: Doc comments read as sentences, unknown enum values and error codes carry their number, no empty
> NEXT: none

# Readable Comments and Diagnostics

## Planned Work

- Join Zig doc text to the Go identifier as one sentence instead of concatenating two capitalized
  words.
- Report the numeric value in an enum `String()` default branch and the unrecognized code in the
  generated error message.
- Give a borrowed reference its concrete handle type instead of `any` plus a per-call interface
  assertion. This landed with the naming phase, which already rewrote the same templates.
- Skip removing the empty helpers file. The update and staleness steps list a fixed set of paths at
  build-graph construction, so a file the generator may or may not emit would have to be discovered
  before generation runs. A two-line file is a smaller cost than making the graph dynamic, and
  `go-check` would report the already committed ones as obsolete for every user to delete by hand.

## Done When

- Doc comments read as sentences, unknown enum values and error codes carry their number, and every
  example regenerates, vets and tests clean.
