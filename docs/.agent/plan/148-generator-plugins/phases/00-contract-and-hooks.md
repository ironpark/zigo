---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zig build test` passes and `scripts/update-generator-cases.sh` reports no updates.
> NEXT: none

# Contract and hook points

## Planned Work

- Add `src/plugin.zig` with `Plugin`, `Context`, `Import`; re-export `emit.Emitter`.
- Add `src/gen/plugins/registry.zig` with an empty built-in list; make
  `emit.publicEmitters()` and `unionFilesAlloc` include registry `files`.
- Call `method_hook` after each public method (after the `Must`/iterator spot in
  `public.zig`) and `type_hook` after each handle, value struct and enum in
  `public_types.zig`; thread `Context` construction through `renderPublic*`.
- Extend `writePublicImports` with the registry's declared imports (used-only).
- Unit test: a test-only plugin registered through a test registry adds a method to a
  handle and a file; goldens unchanged.

## Done When

- `zig build test` passes and `scripts/update-generator-cases.sh` reports no updates.
