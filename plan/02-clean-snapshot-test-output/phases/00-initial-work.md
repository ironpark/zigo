---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Snapshot mismatch detection and diagnostic formatting remain covered, `zig build test` passes, and its default successful output is empty.
> NEXT: none

# Initial Work

## Planned Work

- Add a writer-targeted render method and retain the stderr-facing CLI wrapper.
- Update the corrupted snapshot test to render into a bounded in-memory buffer and assert the exact diagnostic.
- Run focused and full test commands, including a plain-output check.

## Done When

- Snapshot mismatch detection and diagnostic formatting remain covered, `zig build test` passes, and its default successful output is empty.
