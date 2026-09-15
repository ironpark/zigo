---
perf_phase: false
status: in-progress
---
> DONE-WHEN: A test plugin option of type `plugin.ref.Type` written as `.target = api.typeRef("Context")` round-trips to `ext` as a path and resolves to the `TypeDecl` in a test; an unknown path yields `TEST002`.
> NEXT: none

# Reference-typed options

## Planned Work

- Add `plugin.ref` namespace: `Type { path }`, `Function { path }`, `Interface { name }` with `jsonStringify`/`jsonParseFromValue` as bare strings. Allow them (and slices/optionals of them) as fields of any `*Options` struct.
- Authoring: extend `pluginOptions(P, entry)` to map wire ref fields to authoring types: a `plugin.ref.Type` field accepts `zigo.TypeRef` (from `api.typeRef("X")` or `Handle.typeRef()`), `plugin.ref.Function` accepts `zigo.FunctionRef` (`api.ref("f")`), `plugin.ref.Interface` accepts the `Entry` returned by `zigo.interface(...)` or its name. At `use` time verify the referenced declaration belongs to the same `zigo.define` (compile error otherwise) and encode the semantic path.
- `normalize.zig`/`walk.zig`: the encoded path must match the paths the reflector writes (`TypeDecl.source`/name, `SemanticFn.path`), including after plugin `name_type` renames (store the native path; resolution maps to the current name).
- Generator: `ContextBase.resolveType(ref) !?*const TypeDecl`, `resolveFunction(ref) !?*const SemanticFn`, `resolveInterface(ref) !?AbiInterface`; a core validation pass reports `<NAME>002` for every unresolved ref found in any plugin's decoded options (walk the option struct reflectively).
- TEST plugin gains ref-typed options with a golden and contract tests (resolved, unresolved, wrong kind at comptime via `tests/binding_errors`).
- Contract 7.0; docs `api-reference.md` (ref types, resolve helpers), `binding-api.md` (`use` with refs); CHANGELOG "Plugin API 7.0" table started.

## Done When

- A test plugin option of type `plugin.ref.Type` written as `.target = api.typeRef("Context")` round-trips to `ext` as a path and resolves to the `TypeDecl` in a test; an unknown path yields `TEST002`.
- Goldens and examples byte-identical.
