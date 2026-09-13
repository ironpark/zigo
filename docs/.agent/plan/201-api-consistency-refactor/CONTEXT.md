# SCOPE

`src/root.zig`, `src/dsl.zig`, `src/author.zig`, `src/declare.zig`, `src/features.zig`, `src/param.zig`,
`src/result.zig`, `src/normalize.zig`, `build.zig`, `src/build_options.zig`, `src/gen/cli.zig`,
`src/gen/emit/*`, `src/gen/naming.zig`, `src/plugin.zig`, `plugins/*`, `docs/**`, `examples/*`.

# CONTEXT

## Current implementation and bottlenecks

Audit findings (2026-09-14) grouped by surface:

DSL: type constructors `handle/val/materialized/enumType/taggedUnion/callback` mix styles; handle members
can be declared via `.members()`, `api.in()`, or `.context().define()/.select()`; `named/documented/members`
alias `with`; `zigo.define` vs `Context.define` collide; helper form (`zigo.param.output`) and literal form
(`.contract = .{ .buffer = ... }`) are both public; `Lifetime.borrowed` is a one-variant enum; `.root` is
repeated after `scope(library)`; `zigo.dsl` namespace duplicates root and is unused; `declare.zig` legacy
builders (`Function.with/extend/...`, `Methods.strip_prefix`) are unreachable; `features.zig` fakes the
Plugin type and `features.text` is not a real plugin; parameters are referenced by positional index.

build.zig/CLI: `abi-check` step lacks language prefix and collides for Go+Rust; CLI keeps
`--backend`+`--link-mode` although API has `Link`; six package-naming knobs with implicit colocation rule;
four ldflags merge policies; `Options.plugin_config` duplicates `PluginModule.config`; stale `Must*` doc
comment at build.zig:134; `library_loading` is purego-only but top-level; every example repeats
`bindings`, `go_dir`, `abi_base`, `coverage-json` option and the purego twin declaration; Rust path shares
`semantic.json`/`errors.lock.json` paths with Go and passes a meaningless `--go-module`.

Generated Go: multi-package builds export `ZigoAcquire/ZigoRelease/ZigoPoison/...` on every handle; raw
package is public in examples 02 and 07; `Must*` mirror exists only when the plugin is on; `Checked` suffix
has three meanings; `implements` keeps both original and stdlib-shaped methods with differing count types;
callback type names stutter (`EventQueueSetObserverObserver`); optional input `*T` vs output `(T, bool)`;
package may be named `errors`; `Option`/`With*` are unprefixed package globals; `Sink`/`Source` lack
interface assertions.

Plugin API: doc comments reference `extend(...)` (real method is `use`); docs say `targets` (field is
`subjects`); contract version stated as 3.0 and 3.1; three ways to read options
(`functionOptions/typeOptions`, `optionsOf`, `readOptions`); `plugin.Options` exposes ~40 emitter fields;
`Facts` reachable two ways; `Options.plugins` filter is test-only.

## Target structure and invariants

One spelling per concept. Helpers are the only public authoring surface; literal IR is private.
Generated identifiers starting with `zigo` are unexported. Build options that only apply to one `Link`
variant live in that variant's payload.
