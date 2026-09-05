---
completed_at: "2026-09-05T07:26:27Z"
depends_on:
- "109-109-go-generator-restructure#0"
- "109-109-go-generator-restructure#4"
- "109-109-go-generator-restructure#5"
perf_phase: false
status: done
---
> DONE-WHEN: Docs describe every new directory; `zig build test` green.
> NEXT: none

# Document the layout

## Planned Work

- Update `docs/development.md` with the `src/gen/emit/`, `src/gen/validate/`
  and `build/` layout and the rule that shared decisions live in lowering.
- Add a CHANGELOG entry under Unreleased.

## Done When

- Docs describe every new directory; `zig build test` green.
