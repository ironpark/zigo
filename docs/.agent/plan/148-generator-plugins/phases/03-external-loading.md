---
completed_at: "2026-09-07T10:11:03Z"
depends_on:
- "148-generator-plugins#2"
perf_phase: false
status: done
---
> DONE-WHEN: A plugin package outside `src/` is compiled into `zigo-gen` through `.plugins` and its
> NEXT: none

# External plugins: build wiring and cases

## Planned Work

- `addGoBindings(.plugins: []const *std.Build.Module)`; `build/modules.zig` writes a
  `plugin_registry.zig` (`pub const plugins = .{ @import("p0"), ... }`) with
  `addWriteFiles` and imports each module as `p<n>`; `registry.zig` imports it when
  present.
- Generator cases: `options.json` `plugins: ["satisfies"]` resolves against an in-tree
  test registry so plugin goldens run in `zig build test`.
- `docs/plugins.md` (contract, hooks, options, diagnostics, testing a plugin);
  `docs/configuration.md` `.plugins`; cheatsheet row.

## Done When

- A plugin package outside `src/` is compiled into `zigo-gen` through `.plugins` and its
  golden case passes.
