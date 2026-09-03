---
perf_phase: false
status: planned
---
> DONE-WHEN: The two reported functions show their real blockers and every offending parameter; writer-only functions report "not listed"; tests green.
> NEXT: none

# Accurate signature reasons

## Planned Work

- `src/reflect/coverage.zig` `signatureReason` returns the first parameter's reason and reports `*std.Io.Writer` / `*std.Io.Reader` as "writer param, no metadata" although stream parameters bind without metadata (`encodeKey` binds with only `.params`). Report `Screen.dumpString(self, writer, opts: struct { tl: Pin, ... })` and `RenderState.string(self, writer, map: ?struct { alloc: Allocator, ... })` as blocked by `opts`/`map`, not the writer.
- Make the reason name the offending parameter and list every offender, e.g. `param opts: plain struct (field tl: Pin unregistered); param map: optional of plain struct`, joined with `; `; drop the writer/reader reason entirely; keep the allocator/io "no metadata" reasons only when the binding lacks the injection option; descend one level into plain struct and optional to name the first offending field.
- Unit tests in `coverage.zig` for the writer case, the multi-offender case, and the nested struct field case.

## Done When

- The two reported functions show their real blockers and every offending parameter; writer-only functions report "not listed"; tests green.
