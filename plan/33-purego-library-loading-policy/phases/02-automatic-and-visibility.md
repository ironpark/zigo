---
depends_on:
- "33-purego-library-loading-policy#1"
perf_phase: false
status: planned
---
> DONE-WHEN: An automatic example calls no loader function, a failure names every candidate, the public
> NEXT: none

# Automatic Loading and Loader Visibility

## Planned Work

- Load on first binding call when `automatic` is set, at most once, without deadlocking against an
  explicit call, and panic with the aggregate candidate error when every candidate fails.
- Omit the public loader wrappers and unexport the raw loader when `exported_api` is false, and
  keep the bound public API identical across all policies.
- Cover concurrent first use, an explicit call that follows a failed automatic attempt, and the
  panic message with tests.

## Done When

- An automatic example calls no loader function, a failure names every candidate, the public
  declarations of the bound API match the default policy, and race-free first use is tested.
