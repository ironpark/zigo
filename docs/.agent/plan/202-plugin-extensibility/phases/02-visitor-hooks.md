---
depends_on:
- "202-plugin-extensibility#1"
perf_phase: false
status: planned
---
> DONE-WHEN: `grep -rn "method_hook\|type_hook\|file_hook\|package_hook" src plugins docs` returns nothing.
> NEXT: none

# Visitor hooks

## Planned Work

- Define `plugin.Node` as a tagged union: `package_begin/package_end`, `file_begin/file_end(FileInfo)`, `type(TypeDecl)`, `function(AbiFn)`, `param(AbiFn, index)`, `result(AbiFn)`, `field(TypeDecl, index)`, `enum_tag(TypeDecl, index)`.
- Replace `method_hook`, `type_hook`, `file_hook`, `package_hook` with one `visit: ?*const fn (Context, Node, *Builder) anyerror!void`. Keep `replaces_method` semantics as a `claims: ?*const fn (Context, Node) anyerror!bool` that applies to functions (and optionally fields for accessor replacement).
- The emitter walks the IR once per render pass and calls `visit` at each node in document order; per-node output is appended after the generator's own output for that node (the existing insertion points), so current behaviour is reproducible.
- Port every shipped and built-in plugin to `visit`. Remove the old hook fields.
- Docs and `tests/plugin_contract.zig` updated.

## Done When

- `grep -rn "method_hook\|type_hook\|file_hook\|package_hook" src plugins docs` returns nothing.
- Goldens and examples byte-identical; root and plugin tests pass.
