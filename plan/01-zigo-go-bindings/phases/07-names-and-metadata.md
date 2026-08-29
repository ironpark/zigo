---
completed_at: "2026-08-29T23:30:23Z"
depends_on:
- "01-zigo-go-bindings#6"
perf_phase: false
status: done
---
> DONE-WHEN: A function annotated with sidecar names produces a Go signature using those names.
> NEXT: none

# Parameter names and semantic metadata

## Planned Work

- Implement the three-tier name resolution: the sidecar `.params` tuple first, then a
  best-effort `std.zig.Ast` scan of the module root and the files `bindings.zig`
  references directly, then `p0, p1, ...` with a warning. Record which tier supplied
  each name in the IR.
- Restrict the AST pass to syntax: collect parameter names and doc comments only, and
  never let it influence a type decision.
- Add `semantic` (utf8_string, c_string, opaque_bytes), `retention` and `direction` to
  the DSL and honour them during lowering.
- Map `[]const u8` to `[]byte` by default and to `string` under `utf8_string`.
- Carry collected doc comments into the generated Go doc comments.

## Done When

- A function annotated with sidecar names produces a Go signature using those names.
- A UTF-8 string round-trips from Go to Zig and back unchanged.
- A function with no name information still generates, using `p0`-style names and
  emitting a warning.
