---
completed_at: "2026-09-06T03:25:45Z"
depends_on:
- "131-codepoint-reach#0"
perf_phase: false
status: done
---
> DONE-WHEN: Callback case output compiles in the example and round-trips a rune; tests green.
> NEXT: none

# Callback signatures

## Planned Work

- `Callback.param_semantics` / `Callback.return_semantic`; registered callback entries accept `.param_semantics` and `.semantic`; ZIGO053 for non-`u32` scalars; abi_diff comparison.
- Public callback type spells `rune`; handle constructors emit an adapter closure (generalizing the packed adapter) when any hint applies.
- Generator case with a `rune` callback (cgo + purego); example 04 or a new test in it; docs.

## Done When

- Callback case output compiles in the example and round-trips a rune; tests green.
