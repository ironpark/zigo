---
completed_at: "2026-09-07T08:43:04Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test` passes and the `OnLocation`/`PickLocation` constructors in both
> NEXT: none

# Enum callback adapters

## Planned Work

- Make `callbackNeedsAdapter` return true for enum parameters and enum results.
- Give `writeCallbackAdapter` a `PublicScope` and convert enum parameters with
  `writeEnumFromRaw` and enum results (plain or `go_error` pair) with `writeEnumToRaw`.
- Regenerate the `callback_enum_handle` goldens and review the diff.
- Update the enum row of the callback value-type table in `docs/bindings-callbacks.md`.

## Done When

- `zig build test` passes and the `OnLocation`/`PickLocation` constructors in both
  goldens store closures matching the raw `func(int32)` / `func(int32) int32` assertions.
