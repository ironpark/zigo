---
completed_at: "2026-09-06T15:02:15Z"
perf_phase: false
status: done
---
> DONE-WHEN: Removing the three-line block from a call site whose callback type declares
> NEXT: none

# Callback contract defaults

## Planned Work

- A `.repr = .callback` entry accepts `retention`, `reentrancy` and `thread`,
  and every parameter of that registered callback type inherits them.
- `param_meta` at the call site overrides field by field; the recorded document
  is what it is today, so emitters and docs are untouched.
- Reflection tests: inheritance, per-field override, and a retained default
  reaching the retained-callback machinery.

## Done When

- Removing the three-line block from a call site whose callback type declares
  it leaves `semantic.json` unchanged.
