---
completed_at: "2026-08-29T04:16:29Z"
depends_on:
- "01-zigo-go-bindings#1"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build go` in `examples/01-scalar` produces a `semantic.json` describing
> NEXT: none

# Reflector over scalar declarations

## Planned Work

- Implement the minimal `zigo.define` DSL in `src/root.zig`, accepting `.functions`.
- Write `src/reflect/main.zig` rooted on `@import("bindings")`, plus `walk.zig` which
  iterates the declarations with `inline for` and dispatches on `@typeInfo`.
- Handle scalar types and free functions only: integers, floats, bool, void.
- Emit `semantic.json` on stdout and `layout.json` separately, keeping `@sizeOf`,
  `@alignOf` and `@offsetOf` results out of the semantic document.
- Wire reflector construction inside `addGoBindings` by module composition — create a
  `bindings` module importing `zigo` and the user module, and import it from the fixed
  reflector root — with no source synthesis or temporary files. Capture stdout as a
  `LazyPath`.
- Add a golden JSON test for the reflector output of `examples/01-scalar`.

## Done When

- `zig build go` in `examples/01-scalar` produces a `semantic.json` describing
  `add(a: i32, b: i32) i32` with fallback parameter names.
- The reflector compiles against the user module's own dependencies, options and target.
- The golden JSON test passes and fails loudly if `@typeInfo` output shape changes.
