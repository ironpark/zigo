# SCOPE

`src/plugin.zig`, `src/plugin/format.zig` (to become the builder), `src/plugin/site.zig`, `src/author.zig`,
`src/declare.zig`, `src/normalize.zig`, `src/gen/ir/semantic.zig`, `src/reflect/walk.zig`, `src/gen/emit/*`
where hooks are invoked, `src/gen/plugins/*`, `plugins/*/src/plugin.zig`, `src/gen/validate/*`, `src/gen/abi_diff.zig`,
`tests/plugin_contract.zig`, `tests/generator_cases/*`, `docs/plugins/*`, `docs/reference/binding-api.md`.

# CONTEXT

## Current implementation and bottlenecks

- `Extensions` (`src/gen/ir/semantic.zig:835`) is present only on `SemanticFn.ext` (l.940) and `TypeDecl.ext` (l.1196). `Param` (l.~500) has `go: ?ParamGo` but no `ext`; value/handle fields and enum fields have none.
- `Entry.use` (`src/author.zig:238`) appends `ir.Extension` to `Function.extensions` or `Type.extensions` only. `Param` (`src/author.zig`) has no `use`.
- `Plugin` (`src/plugin.zig:~525-590`) has `FunctionOptions`/`TypeOptions` and `subjects` over 8 declaration kinds; hooks are `method_hook(Context, writer, AbiFn)`, `type_hook(Context, writer, TypeDecl)`, `file_hook`, `package_hook`, `replaces_method`.
- `Writers` (`src/plugin.zig:309-337`) is a flat vtable of 14 function pointers; `src/plugin/format.zig` implements the four generic helpers. `plugins/json/src/plugin.zig` still writes `"\tswitch text {\n"` and similar statement text by hand.
- Built-ins: `src/gen/plugins/iterator.zig` and `implements.zig` read `ext` (since 201 phase 4) but the reflector also fills `SemanticFn.go.iterator/implements` (`goIterator()`, `goImplements()`, `goImplementsHidesOriginal()` at `semantic.zig:1067-1094`) which `abi_diff.zig`, `validate/functions.zig`, `validate/names.zig`, `emit/common.zig` and `plugins/must.zig` consume. `IMPLEMENTS` declares `subjects = {function, handle}` on the generator side while `zigo.features.implements` is function-only.

## Target structure and invariants

- One `Extensions` field per IR node kind that a declaration can `use` on: function, type, param, result, field, enum tag.
- Plugin declares per-subject option types; `subjects` covers node kinds, not just declarations.
- Hooks are a visitor: `visit: fn(Context, Node, *Builder) !void` where `Node` is a tagged union over the IR node kinds plus file/package boundaries. The old position hooks are removed.
- `Builder` is the only Go rendering path exposed to plugins; `Writers` becomes an implementation detail of the builder.
- Core rules read iterator/implements facts through the same `ext` decode the plugins use; the `go.*` typed shortcuts are gone.
