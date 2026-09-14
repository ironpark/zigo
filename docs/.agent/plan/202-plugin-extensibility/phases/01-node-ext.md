---
depends_on:
- "202-plugin-extensibility#0"
perf_phase: false
status: planned
---
> DONE-WHEN: `zigo.param.input(1).use(P, .{ ... })` and a field-level `use` compile, appear in `semantic.json`, and are readable by the test plugin.
> NEXT: none

# Node-level extensions and DSL use

## Planned Work

- IR: add `ext: ?Extensions` to `Param`, `Returns`/result node, `ValueField`, `HandleField`, `EnumField` (value/handle/enum declarations) in `src/gen/ir/semantic.zig`; serialize under the same `ext` key rules; parse-time round-trip tests.
- Authoring: `Param.use(P, opts)` and `Returns.use(P, opts)` on `src/author.zig` types; `HandleField`/`ValueField`/`EnumField` gain `use` (or an `extensions` field plus a `zigo.field(...)` builder if fields are plain structs today). `normalize.zig` and `reflect/walk.zig` carry them into the IR.
- Plugin: `Plugin` gains `ParamOptions`, `ResultOptions`, `FieldOptions`, `TagOptions` type slots; `Subject` gains `.param, .result, .field, .enum_tag`; `optionsOf` accepts the new attachment kinds; `site.zig` gains `paramSite`, `fieldSite`, `tagSite`.
- Validation: unknown subject for a plugin is a compile error at `use` and a diagnostic at generation, same as today for declarations.
- Add a test plugin case in `src/gen/plugins/testing.zig` that reads a param option and a field option, with a generator golden.
- Docs: `docs/plugins/api-reference.md`, `authoring.md`, `docs/reference/binding-api.md`.

## Done When

- `zigo.param.input(1).use(P, .{ ... })` and a field-level `use` compile, appear in `semantic.json`, and are readable by the test plugin.
- Existing goldens unchanged; new golden covers the four node kinds.
