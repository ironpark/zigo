---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Both CI jobs install Go 1.26.x, the workflow no longer selects Go 1.24.x, and the scoped fix is committed.
> NEXT: none

# Initial Work

## Planned Work

- Update both `actions/setup-go` steps in CI from Go 1.24.x to Go 1.26.x and verify the workflow consistently selects the newer toolchain.

## Done When

- Both CI jobs install Go 1.26.x, the workflow no longer selects Go 1.24.x, and the scoped fix is committed.
