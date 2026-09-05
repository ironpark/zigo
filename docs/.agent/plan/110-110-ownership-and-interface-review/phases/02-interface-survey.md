---
perf_phase: false
status: planned
---
> DONE-WHEN: `docs/.agent/design/11-comptime-interfaces.md` lists the patterns, what is
> NEXT: none

# Comptime interface survey

## Planned Work

- Catalogue the interface patterns Zig code uses: vtable structs
  (`std.mem.Allocator` style), `anytype` parameters with duck-typed method
  calls, tagged unions dispatching by tag, and generic containers
  instantiated per element type.
- For each pattern, determine what `walk.zig` can see at comptime (method
  names and signatures per concrete type) and what it cannot (which types
  an `anytype` parameter accepts).
- Find one existing example per pattern in `examples/` or the tests, or
  write a minimal fixture, and record the Go the user would want.

## Done When

- `docs/.agent/design/11-comptime-interfaces.md` lists the patterns, what is
  reflectable, and a Go sketch per pattern.
