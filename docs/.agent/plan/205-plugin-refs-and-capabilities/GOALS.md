# GOALS

## Problem and the end result from the user's point of view

Plugin options cross to the generator as JSON, so a plugin that needs to name a type, a function or a
generated interface takes a string (`satisfies` takes `"io.Closer"`) and nothing checks it at the
declaration. Plugins also cannot share knowledge: `Facts` are private per plugin, so `interfaces.zig`
imports `must.zig` directly and a third-party plugin cannot ask "does this function have a Must
variant". A plugin author should be able to declare option fields typed as references that the
`bindings.zig` author writes with `api.typeRef(...)`/`api.ref(...)`/interface entries, checked at
comptime and resolved at generation, and to publish and consume capabilities with typed facts so that
dependencies are expressed by what a plugin provides rather than by its name.

## Measurable goals

- `satisfies` accepts a generated `zigo.interface` reference or a known stdlib interface and rejects unknown names at generation with a diagnostic; a wrong reference kind is a comptime error at the declaration.
- `interfaces.zig` no longer imports `must.zig`; it consumes a capability. `json` emits different `UnmarshalJSON` when `enumkit` provides `IS_KNOWN` for the enum.
- Contract 7.0; generated Go and Rust byte-identical for bindings that use no new feature.

## Supported scope and non-goals

In scope: reference option types and their JSON wire form, comptime checks in `use`, generation-time resolution helpers, capability declarations, shared typed facts, ordering by capability, built-in and shipped plugin ports, docs, tests.
Out of scope: distribution helpers, a plugin test kit beyond what these phases need.

## Reference source / commit / license

Baseline: tag 0.28.0 (commit 44b14c45). MIT.

## Completion criteria for the whole plan

All four phases done; `docs/plugins/*` describe contract 7.0; CHANGELOG `Unreleased / Changed (breaking)` has a "Plugin API 7.0" table.
