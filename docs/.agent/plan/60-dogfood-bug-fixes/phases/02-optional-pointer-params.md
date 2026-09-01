---
completed_at: "2026-09-01T20:42:59Z"
perf_phase: false
status: done
---
> DONE-WHEN: Fixture tests pass with nil and non-nil on both backends; `zig build test` green;
> NEXT: none

# Optional opaque-pointer parameters

## Planned Work

- Add an `.optional` branch to typeNode in src/reflect/walk.zig for optional opaque
  pointers (`?*T`, `?*const T`), setting `opaque_ptr.nullable = true`; other optional
  payloads get a clear `@compileError` naming optionals.
- Thread nullability through validate/lower/emit: Go parameter stays the handle type,
  nil marshals as NULL (no HandleError for nullable params); C/shim signatures allow
  null. Keep cgo and purego backends in lockstep, including callback-signature rules
  if optionals appear there (out of scope for callback params — reject with the
  existing/most-specific diagnostic if hit).
- Add fixture/example coverage (e.g. a `?*const CancelToken`-style parameter) with
  tests passing nil and non-nil; update goldens and docs/bindings.md.

## Done When

- Fixture tests pass with nil and non-nil on both backends; `zig build test` green;
  committed.
