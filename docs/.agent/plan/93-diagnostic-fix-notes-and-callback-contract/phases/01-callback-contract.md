---
completed_at: "2026-09-03T00:27:39Z"
perf_phase: false
status: done
---
> DONE-WHEN: Generated Go docs show the contract lines for a callback that sets them; snapshots and verification loop green.
> NEXT: none

# Callback contract metadata

## Planned Work

- `.reentrancy` and `.thread` on callback `param_meta`; reflect, IR, validation (misuse on non-callback params is a diagnostic reusing the existing param_meta misuse code if one exists), Go doc rendering; generator case snapshot; docs; CHANGELOG `### Added`.

## Done When

- Generated Go docs show the contract lines for a callback that sets them; snapshots and verification loop green.
