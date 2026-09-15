# SCOPE

`src/author.zig` (`authoredOptions`/`Authored`, `Entry.use`, `Param.use`, `Returns.use`), `src/declare.zig`
(`HandleField.extend`, `ValueField.use`, `EnumField.use`), `src/normalize.zig`, `src/root.zig` re-exports,
`plugins/json/src/plugin.zig`, `plugins/json/README.md`, `src/gen/emit/public_types.zig` (`Parse<Type>` shape),
`tests/generator_cases/plugin_json_enumkit`, `tests/binding_errors/`, `docs/reference/binding-api.md`,
`docs/plugins/api-reference.md`, `docs/plugins/authoring.md`, CHANGELOG.

# CONTEXT

## Current implementation and bottlenecks

- `src/declare.zig:240` `ValueField.use(P: anytype, value: P.FieldOptions)` and `:262` `EnumField.use(P, value: P.TagOptions)` take the plugin's wire option type directly; `src/author.zig` `Entry.use` (l.~271) goes through `authoredOptions(P, subject)` which maps `plugin.ref.*` fields to `TypeRef`/`FunctionRef`/interface entries and checks roots. `declare.zig` imports only `std` and `plugin`; `author.zig` imports `declare.zig` as `ir`, so the dependency runs one way.
- `plugins/json/src/plugin.zig` `renderEnum`: with the `enum_known` fact present it renders the `Values()`/`IsKnown()` loop; otherwise a `switch`. `src/gen/emit/public_types.zig:~1057-1076` emits `Parse<Type>(text string) (<Type>, error)` returning `*EnumParseError` when `EnumOptions.text` is set; `TypeDecl` carries `text: ?bool` (`semantic.zig:~1220`).

## Target structure and invariants

- One mapping function (`authoredOptions`) serves every `use` site. Field and tag `use` either move to `author.zig` (with `declare.zig` keeping plain data structs) or `declare.zig` receives a comptime hook so it can call the mapping without importing author types.
- json's decode order: `Parse<Type>` when the enum has `.text`, else the `Values()` loop when `enum_known` is present, else the `switch`. `IsKnown()` gates membership in the first two cases.
