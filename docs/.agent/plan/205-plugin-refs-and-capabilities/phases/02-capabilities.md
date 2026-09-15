---
completed_at: "2026-09-15T09:38:18Z"
depends_on:
- "205-plugin-refs-and-capabilities#1"
perf_phase: false
status: done
---
> DONE-WHEN: `grep -rn "@import(\"must.zig\")" src/gen/plugins` returns nothing outside `must.zig`'s own tests and `registry.zig`.
> NEXT: none

# Capabilities and shared facts

## Planned Work

- `plugin.Capability = struct { name: []const u8, Facts: type }`; `Plugin.provides: []const Capability`, `requires: []const Capability` (hard, missing provider is a comptime error, orders after), `uses: []const Capability` (soft, orders after when present). Remove string `after`/`requires`.
- `Facts.put(cap, id, value)` callable only by a provider of `cap` (checked at comptime through the calling plugin's `provides` list, or at runtime by the analyze context); `Facts.get(cap, id)` by anyone. `context.provided(cap) bool` tells a consumer whether a provider is registered and enabled.
- Built-in port: `MUST` provides `plugin.capabilities.must_variant` (`Facts = struct { name: []const u8 }`); `INTERFACES` `uses` it and drops the `must.zig` import. Move shared capability definitions to `src/plugin/capabilities.zig`, importable by shipped plugins.
- Ordering: `ordered()` derives edges from capabilities; duplicate providers of one capability are a comptime error unless the capability is marked `multi = true`.
- Tests: contract tests for provider/consumer ordering, missing provider, soft `uses` without provider, `Facts` type safety across plugins; update `tests/plugin_contract.zig`, docs `api-reference.md` (Capabilities section), CHANGELOG.

## Done When

- `grep -rn "@import(\"must.zig\")" src/gen/plugins` returns nothing outside `must.zig`'s own tests and `registry.zig`.
- `grep -rn "\.after = \|\.requires = &.{\"" src plugins tests` finds no string-based ordering.
- Goldens and examples byte-identical.
