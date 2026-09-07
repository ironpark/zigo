---
depends_on:
- "156-binding-authoring-polish#0"
- "156-binding-authoring-polish#1"
perf_phase: false
status: planned
---
> DONE-WHEN: Examples and docs demonstrate all improvements, validation passes and the final commits leave a clean working tree.
> NEXT: none

# Idiomatic examples and documentation

## Planned Work

- Remove source-equivalent parameter names; keep intentional overrides and all semantic contracts.
- Use local scopes, member groups, explicit shared selectors, shared result contracts and readable layouts in examples.
- Update all current API docs and migration guidance; retain one explicit full-contract example.
- Compare semantic content allowing only intentional provenance and ordering changes, run full tests, all example ABI/generated-tree checks and fresh cgo/purego Go tests.

## Done When

- Examples and docs demonstrate all improvements, validation passes and the final commits leave a clean working tree.
