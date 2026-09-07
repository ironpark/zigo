# GOALS

## Problem and the end result from the user's point of view

Every Go-surface convenience (`.iterator`, `.implements`, `Must*`, `.interfaces`) is a
change to zigo itself: a declaration key, a validator, an emitter, docs, a release. Users
who want `MarshalJSON` on their value structs, functional options on a constructor, or a
`var _ mypkg.Sink = (*Stream)(nil)` assertion have to fork or hand-write. After this plan:

- A plugin is an ordinary Zig package. It owns a typed `Options` struct, validates its
  own declarations, and adds Go code through three hooks. It never touches the shim, the
  C header or the raw package, so it cannot break the ABI and works on cgo and purego.
- The binding author imports it in `bindings.zig` and lists it in `build.zig`:

  ```zig
  const implements = @import("zigo_implements");
  .functions = &.{ implements.writer(zigo.dsl.func("Stream.feed")) },
  ```
  ```zig
  zigo.addGoBindings(b, .{ ..., .plugins = &.{ b.dependency("zigo_implements", .{}).module("plugin") } });
  ```
- zigo's own `.iterator`, `.implements`, `Must*` and `.interfaces` run through the same
  hooks, so the frame is exercised by every existing golden and example.

## Measurable goals

- `src/plugin.zig` is the whole public plugin API; a plugin compiles against it alone.
- Four built-in features migrated with every generator golden and example tree byte-identical.
- An out-of-tree showcase plugin (`plugins/satisfies`) is consumed by example 11 through
  `build.zig.zon` + `.plugins`, on cgo and purego, with its own golden case.
- A malformed plugin option in a hand-written `semantic.json` is a plugin-prefixed
  diagnostic (`SATIS001`), never a panic; a wrong field in `bindings.zig` is a Zig
  compile error at the declaration.
- `docs/plugins.md` lets someone write a plugin without reading generator source.

## Supported scope and non-goals

In scope: the contract, typed extension transport, hooks (after a method, after a type,
extra public files), build-time registry, plugin validation and diagnostics, `abi-diff`
and `doctor` awareness, generator-case support for plugin cases, docs, two showcases.

Non-goals: hooks into `shim.zig`, the header, or `raw`; out-of-process (JSON-pipe)
plugins; plugin-defined declaration *fields* on `zigo.Function` (transport is `ext`);
plugin ordering guarantees beyond registration order; a plugin marketplace/index.

## Reference source / commit / license

- Emitter registry: `src/gen/emit/emit.zig` `Emitter`, `core_emitters`, `public_emitters`.
- Helper pruning re-renders public emitters: `src/gen/emit/references.zig:84`.
- Public file prelude and body-derived imports: `src/gen/emit/public.zig:779`, `:922`.
- Generator is compiled per project from dependency source: `build.zig:336` and
  `build/modules.zig` `createGeneratorModules` / `addGeneratorWithModules`.
- Precedent features to migrate: `src/gen/emit/{iterators,implements,must,interfaces}.zig`,
  `src/gen/validate/{functions,interfaces,names}.zig`, `src/gen/abi_diff.zig:145`.

## Completion criteria for the whole plan

`zig build test` passes; all examples regenerate with no diff before phase 4 and with only
the showcase additions after; `scripts/release.sh` checks pass; `docs/plugins.md`,
`docs/configuration.md` (`.plugins`), `docs/cheatsheet.md`, `CHANGELOG.md` updated.
