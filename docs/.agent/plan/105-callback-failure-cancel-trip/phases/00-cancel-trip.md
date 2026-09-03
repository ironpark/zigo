---
completed_at: "2026-09-03T06:16:09Z"
perf_phase: false
status: done
---
> DONE-WHEN: The new example test passes on both backends and no golden changes for bindings without `.cancel`.
> NEXT: none

# Trip the cancel flag on callback failure

## Planned Work

- Store the cancel flag pointer on the callback state for cancellable functions; set it (atomic store 1) in every failure path (panic, deleted token, Go error) on cgo and purego; example test proving a native loop that ignores the return value stops; docs and CHANGELOG.

## Done When

- The new example test passes on both backends and no golden changes for bindings without `.cancel`.
