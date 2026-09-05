---
completed_at: "2026-09-05T09:34:47Z"
perf_phase: false
status: done
---
> DONE-WHEN: The three entry pages are under 350 lines, task-oriented, and link to retained technical details.
> NEXT: none

# Restructure and verify user reference guides

## Planned Work

- Read and group existing sections; split binding recipes and generated implementation references.
- Rewrite limitations as supported choices, lifetime rules and recovery guidance; retain diagnostic details separately.
- Repair incoming links, check section coverage and review misleading or obsolete claims against examples.

## Done When

- The three entry pages are under 350 lines, task-oriented, and link to retained technical details.
- All repository Markdown links to changed guides resolve, headings are coherent, and whitespace checks pass.
- Documentation changes are committed.

## Verification Results

- Entry guides now have 92, 152, and 191 lines; detailed topics retain 58 of 61 original binding code blocks verbatim and correct the other three.
- All 622 local links across 695 Markdown files resolve; user-guide heading levels and code fences pass.
- The revised materialized declaration passes Zig syntax formatting; git diff --check passes.
- Runtime implementation is unchanged; no runtime test suite was required for this documentation restructuring.
