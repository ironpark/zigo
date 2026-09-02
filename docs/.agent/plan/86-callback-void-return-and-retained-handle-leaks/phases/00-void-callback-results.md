---
perf_phase: false
status: planned
---
> DONE-WHEN: A `void`-returning callback generates and its Go test invokes it on both backends; no `unreachable` reachable from a `.void` callback result; `zig build test` green.
> NEXT: none

# Void callback results

## Planned Work

- Reproduce with a unit test in `emit.zig` (or `tests/generator_cases`) using a callback whose `.return` is `.void` on the cgo backend; confirm the unreachable.
- Implement `void` results through the reflect/lower/emit path for cgo and purego: C typedef `void (*)(...)`, Zig shim trampoline, Go exported callback function without a result, purego dispatcher ignoring the result. Keep the Go public callback type as `func(...)` with no return.
- Add a generator case (or extend an existing callbacks case) and update snapshots with `zig build snapshot -- <expected> <actual> --update-snapshots`.
- If some path cannot support `void`, add a diagnostic with the next free code and a `validate.zig` snapshot test instead of reaching `unreachable`; document it in `docs/diagnostics` (or wherever ZIGO codes are listed).

## Done When

- A `void`-returning callback generates and its Go test invokes it on both backends; no `unreachable` reachable from a `.void` callback result; `zig build test` green.
