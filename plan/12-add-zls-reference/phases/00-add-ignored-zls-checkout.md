---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Git reports `ref/zls` as ignored, its origin is official, and its checked-out branch/tag and commit match the selected 0.16.x ref.
> NEXT: none

# Add ignored zls checkout

## Planned Work

- Add `ref/` to `.gitignore`, identify the official 0.16.x ref, and shallow-clone it into `ref/zls`.

## Done When

- Git reports `ref/zls` as ignored, its origin is official, and its checked-out branch/tag and commit match the selected 0.16.x ref.
