# SCOPE

- New: `src/plugin.zig` (public API), `src/gen/plugins/registry.zig` (built-in list and
  the generated-registry import), `src/gen/plugins/{iterator,implements,must,interfaces}.zig`,
  `plugins/satisfies/` (package with `build.zig.zon`), `docs/plugins.md`,
  `tests/generator_cases/plugin_*`.
- Changed: `src/declare.zig` (`ext`, `extend`), `src/dsl.zig`, `src/reflect/walk.zig`
  (write `ext`), `src/gen/ir/semantic.zig` (`ext` on functions and types, round trip),
  `src/gen/validate/validate.zig` (plugin validators), `src/gen/emit/{emit,public,references}.zig`
  (hooks, emitter list from registry, plugin imports), `src/gen/abi_diff.zig`,
  `src/gen/doctor.zig`, `build.zig` + `build/modules.zig` (`.plugins`, generated registry),
  `build/tests.zig` (plugin cases), `examples/11-io-streams`.

# CONTEXT

## Current implementation and bottlenecks

- Emitters are already function-pointer records, but the two lists are comptime arrays
  read in three places (`generator.zig`, `references.zig`, `emit.unionFilesAlloc`).
- Method-adjacent code (`Must*`, iterator, implements) is called by name from one spot
  in `public.zig:766-770`; type-adjacent code is scattered across `public_types.zig`.
- Declaration keys are concrete fields on `zigo.Function`; plugins cannot add fields.
- `semantic.json` is parsed into fixed structs; unknown keys are not preserved.
- The generator binary is rebuilt per consuming project already, so a build-time
  registry costs nothing new.

## Target structure and invariants

- **Contract** (`src/plugin.zig`):
  ```zig
  pub const Plugin = struct {
      name: []const u8,                 // ext key, diagnostic prefix, file suffix
      Options: type,                    // std.json-serializable, owned by the plugin
      validate: ?*const fn (Context, semantic.Semantic) anyerror!?diagnostic.Diagnostic = null,
      method_hook: ?*const fn (Context, *std.Io.Writer, abi.AbiFn) anyerror!void = null,
      type_hook: ?*const fn (Context, *std.Io.Writer, semantic.TypeDecl) anyerror!void = null,
      files: []const emit.Emitter = &.{},
      imports: []const Import = &.{},   // non-std imports the hooks may write
  };
  ```
  `Context` carries `program`, `options`, the public scope writers (type names,
  receiver names, signature helpers) and `options(P, function) !?P.Options` /
  `typeOptions(P, decl)`.
- **Typed transport**: `Function.extend(P, value: P.Options)` captures the comptime value
  in a generated encoder; reflection writes `"ext": { "<name>": <json> }`; the generator
  parses with `std.json.parseFromValue(P.Options, ...)`. `SemanticFn.ext` and
  `TypeDecl.ext` are `?std.json.ObjectMap` preserved verbatim through parse/serialize.
- **Hooks are additive and Go-only.** A hook writes into the file that owns the method or
  type, after it; a `files` emitter renders through `renderPublicFile` so its imports
  are derived from the body plus the plugin's declared `imports`. Helper pruning
  re-renders plugin output too, so `zigoBoolToUint8`-style helpers stay demand-driven.
- **Registry**: `registry.zig` exports `plugins: []const Plugin` = built-ins ++ the
  generated `plugin_registry` module's list. Order is registration order.
- **Diagnostics**: plugin codes are `<NAME><nnn>`; `validate.findIssue` runs plugin
  validators after core rules. `abi-diff` reports an `ext` entry added as compatible and
  removed/changed as breaking, keyed by plugin name. `doctor` prints loaded plugins.
- **Built-ins keep their declaration keys** (`.iterator = .{}` and friends stay as sugar
  and keep their `semantic.json` spelling) so existing documents and goldens do not move;
  their validators and emitters live in `src/gen/plugins/*` and run through the hooks.
