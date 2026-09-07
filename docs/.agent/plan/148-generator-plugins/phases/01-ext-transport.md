---
depends_on:
- "148-generator-plugins#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: A test plugin with `Options = struct { mode: enum { a, b } }` reads `.b` from a
> NEXT: none

# Typed extension transport and validation

## Planned Work

- `zigo.Extension { plugin, write }` and `Function.extend(P, value)`, plus `extend` on
  `Handle`, `Value`, `Enum` and `TaggedUnion` entries; `dsl` passes `ext` through.
- Reflection writes `"ext"` on functions and types; `SemanticFn.ext`/`TypeDecl.ext`
  round-trip as raw JSON objects (test with a two-plugin document).
- `Context.options(P, function)` / `typeOptions(P, decl)` parse and cache; parse errors
  become `<NAME>001` diagnostics with the function site.
- `validate.findIssue` runs each registered plugin's `validate` after core rules.
- `abi_diff`: `ext` add compatible, remove/change breaking, per plugin name; test.
- `doctor` lists plugin names.

## Done When

- A test plugin with `Options = struct { mode: enum { a, b } }` reads `.b` from a
  document reflected from `extend`, rejects `{ "mode": "c" }` with `TEST001`, and
  `abi-diff` names the plugin on removal.
