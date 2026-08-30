---
depends_on:
- "20-automatic-binding-discovery#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Unit tests cover root functions, methods, exclusions, overrides, compatibility with `.functions`, and failure cases under Zig 0.16.0.
> NEXT: none

# Opt-in automatic discovery

## Planned Work

- Add a backward-compatible declaration form for discovering public root functions and public methods of registered types.
- Add owner-qualified exclusions and explicit overrides for names and ABI semantics.
- Reject ambiguous, unknown, duplicate, generic, and unsupported selections with actionable diagnostics.

## Done When

- Unit tests cover root functions, methods, exclusions, overrides, compatibility with `.functions`, and failure cases under Zig 0.16.0.
