# GOALS

## Problem and the end result from the user's point of view

After plan 201 the plugin contract (4.0) is consistent but shallow: hooks attach only to whole
types and methods, plugins write Go by string templates, and the built-in iterator/implements
plugins use typed IR fields third parties cannot. A plugin author should be able to attach options
to a parameter, a return value, a struct field or an enum tag; render Go through a builder instead of
`writer.print`; and reproduce any built-in plugin with the public contract alone.

## Measurable goals

- `zigo.param.*(...).use(P, opts)` and field/tag-level `use` compile and reach the plugin through `ext`.
- Shipped plugins (`json`, `enumkit`, `satisfies`) contain no hand-written Go statement text; all Go is emitted through the builder.
- `iterator` and `implements` read nothing from `SemanticFn.go`/`TypeDecl.go` that a third-party plugin cannot read from `ext`.
- Contract bumped to 5.0; generated Go for all goldens and examples byte-identical except where noted per phase.

## Supported scope and non-goals

In scope: `src/plugin.zig`, `src/plugin/*`, `src/author.zig` and `src/declare.zig`/`normalize.zig` for node-level `use`, `src/gen/ir/semantic.zig` ext placement, `src/reflect/walk.zig`, built-in and shipped plugins, docs and tests.
Out of scope: Rust rendering hooks, native-side (shim) contributions, plugin distribution helpers, shared facts between plugins.

## Reference source / commit / license

Baseline: HEAD after plan 201 (commit 4638a493). MIT.

## Completion criteria for the whole plan

All four phases done, contract 5.0 documented in `docs/plugins/*`, CHANGELOG `Unreleased / Changed (breaking)` has a "Plugin API 5.0" table.
