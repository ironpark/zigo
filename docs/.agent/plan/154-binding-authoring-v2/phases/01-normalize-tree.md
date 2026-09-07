---
completed_at: "2026-09-07T12:52:43Z"
depends_on:
- "154-binding-authoring-v2#0"
perf_phase: false
status: done
---
> DONE-WHEN: Tree and flat internal declarations have equivalent semantics in focused tests, with invalid contracts rejected.
> NEXT: none

# Declaration tree normalization

## Planned Work

- Normalize package/type members, references, defaults and original-index parameter overrides to internal declarations.
- Validate duplicate identities, root mismatches, role/receiver/release relationships and preserve deterministic ordering.
- Add equivalence and compile-fail regression tests.

## Done When

- Tree and flat internal declarations have equivalent semantics in focused tests, with invalid contracts rejected.
