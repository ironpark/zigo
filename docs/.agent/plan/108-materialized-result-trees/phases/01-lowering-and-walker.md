---
depends_on:
- "108-materialized-result-trees#0"
perf_phase: false
status: planned
---
> DONE-WHEN: The generator case compiles the shim and header, and a Zig test round-trips a tree through the walker.
> NEXT: none

# Lowering and the Zig walker

## Planned Work

- `MaterializedLayout` table in lowering; versioned buffer layout documented in `docs/abi.md`; generated shim walker and release function; C header declarations; return, error-union, slice and out-parameter positions; generator case pinning shim and header; abi-check layout version.

## Done When

- The generator case compiles the shim and header, and a Zig test round-trips a tree through the walker.
