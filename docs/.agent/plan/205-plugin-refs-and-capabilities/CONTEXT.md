# SCOPE

`src/plugin.zig`, `src/author.zig` (`use`, `pluginOptions`, `TypeRef`, `FunctionRef`, `Interface`), `src/normalize.zig`,
`src/reflect/walk.zig`, `src/gen/ir/semantic.zig` (ext encoding), `src/gen/plugins/*`, `plugins/satisfies`, `plugins/json`,
`plugins/enumkit`, `src/gen/validate/*`, `tests/plugin_contract.zig`, `tests/generator_cases/*`, `docs/plugins/*`,
`docs/reference/binding-api.md`, examples 10 and 11.

# CONTEXT

## Current implementation and bottlenecks

- Options are `std.json`-round-trippable structs (`Plugin.FunctionOptions` etc., `src/plugin.zig:~1115`). `Entry.use` (`src/author.zig:271`) type-checks the literal against `pluginOptions(P, entry)` then encodes to `ir.Extension` JSON; the generator decodes with `optionsOf`.
- `author.TypeRef { root, type, path }` and `FunctionRef { root, container, path, name }` (`src/author.zig:16-30`) exist for the core DSL but cannot appear inside plugin option structs because they hold `type` values that do not serialize.
- `plugins/satisfies/src/plugin.zig:26` `interfaces: []const []const u8`; validation only checks the string is non-empty. Generated interfaces come from `zigo.interface(...)` entries (`author.Interface`, `abi.Program.interfaces`).
- `Facts` (`src/plugin.zig:84-117`) is keyed by `(plugin, DeclarationId)` and typed by `P.Facts`; `get` requires the provider's comptime `Plugin` value. `interfaces.zig:10,83,158` imports `must.zig` for `hasVariant`.
- `Plugin.after` / `requires` (`src/plugin.zig:1129-1131`) order by plugin name strings; `ordered()` (~l.1200-1250) resolves them at comptime.

## Target structure and invariants

- Wire types `plugin.ref.Type`, `plugin.ref.Function`, `plugin.ref.Interface` are plain structs holding the semantic path string (and, for functions, the container path); they serialize as strings and are what plugin option structs declare. On the authoring side `use` accepts `zigo.TypeRef`/`FunctionRef`/an `Interface` entry for those fields, verifies the referenced declaration is registered in the same binding, and encodes the path.
- The generator resolves refs through `context.resolve(ref)` returning the `TypeDecl`/`SemanticFn`/`AbiInterface` or a diagnostic (`<NAME>002` unresolved reference).
- `plugin.Capability = struct { name, Facts: type }` defined once and importable by any plugin; providers list `provides`, consumers list `requires` (hard, orders after) or `uses` (soft, orders after if present). `Facts.put/get` are keyed by capability, so a consumer needs only the capability value, not the provider's `Plugin`.
