---
completed_at: "2026-08-30T11:50:27Z"
depends_on:
- "30-go-user-experience#0"
perf_phase: false
status: done
---
> DONE-WHEN: A minimal consumer registers standard steps with one call, custom names support multiple binding sets, and build-graph tests plus representative examples pass.
> NEXT: none

# Standard Build Steps

## Planned Work

- Extend `GoBindings` with an explicit helper that registers conventional `go`, `go-check`, and optional `abi-check` steps without duplicating user wiring.
- Add collision-safe configuration for projects that expose more than one binding set.
- Migrate repository examples and build tests to exercise the helper while preserving access to individual step handles.

## Done When

- A minimal consumer registers standard steps with one call, custom names support multiple binding sets, and build-graph tests plus representative examples pass.
