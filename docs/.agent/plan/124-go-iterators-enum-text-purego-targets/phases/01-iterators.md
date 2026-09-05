---
completed_at: "2026-09-05T21:21:52Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test --summary all` passes with the new cases.
> NEXT: none

# Iterator wrappers

## Planned Work

- Read `.iterator = .{ .name = ... }` in `walk.zig`; add `SemanticFn.iterator`.
- Validate in `validate/functions.zig`: `ZIGO050` for a free function, a
  method with Go-visible parameters, or a non-optional return; document it.
- Emit the wrapper after the public method in `public.zig`, sharing the
  payload spelling with `must.writeMustResultType`; add `iter` to
  `public_std_imports`; include the wrapper in `interfaces.zig` method
  matching if an interface lists it (or document that interfaces list `Next`).
- `abi_diff.zig`: wrapper removed or renamed is breaking, added is compatible.
- Generator cases `iterator` and `iterator_purego`.
- Add an iterator method to `examples/07-event-queue` (or `03-opaque`),
  regenerate, add a Go range-over-func test.
- Docs: `bindings-handles.md` (new section), `bindings-functions.md` metadata
  table, `generated-runtime.md`, CHANGELOG.

## Done When

- `zig build test --summary all` passes with the new cases.
- The example passes `go-check`, `abi-check` and `go test` with a test that
  ranges over the generated sequence and observes early break and error.
