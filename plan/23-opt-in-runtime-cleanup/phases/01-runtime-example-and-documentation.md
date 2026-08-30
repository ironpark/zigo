---
depends_on:
- "23-opt-in-runtime-cleanup#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Event-queue Zig and Go tests pass and documentation continues to require explicit `Close` as the primary contract.
> NEXT: none

# Runtime example and documentation

## Planned Work

- Enable cleanup in the event-queue example and raise its declared Go version to 1.24.
- Add bounded forced-GC coverage for native allocation and retained callback fallback plus explicit-close non-duplication.
- Document version, reliability, reachability-cycle, concurrency, and thread-affinity constraints.

## Done When

- Event-queue Zig and Go tests pass and documentation continues to require explicit `Close` as the primary contract.
