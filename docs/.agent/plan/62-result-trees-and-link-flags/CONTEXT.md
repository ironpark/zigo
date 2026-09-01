# SCOPE

- `build.zig` (`systemLibraryFlags`, `frameworkFlags`, new lib-path
  collection), `src/gen/emit.zig` `renderRaw` link block, `src/gen/generator.zig`
  option plumbing and tests.
- `docs/configuration.md`, `docs/.agent/design/03-lowering-rules.md` §12,
  `docs/limitations.md`.
- Phase 1: `src/reflect/walk.zig`, `src/gen/validate.zig` (`ZIGO012` relaxation
  under the new axis), `src/gen/lower.zig`, `src/gen/emit.zig` deep-copy paths,
  `src/gen/abi_diff.zig`, `bindings.md`, 03 §6.
- Phase 2: `src/gen/abi_diff.zig`, `build.zig` option, `generated-code.md`.

# CONTEXT

## Current implementation and bottlenecks

- `build.zig:985` `systemLibraryFlags` iterates `module.link_objects` and emits
  `-l{name}` for `.system_lib` only; `use_pkg_config`, `preferred_link_mode`,
  and `weak` are ignored. `frameworkFlags` emits `-framework X` for all
  `module.frameworks`. `lib_paths`, `rpaths`, `include_dirs` are never read.
- `src/gen/emit.zig:951` writes `#cgo LDFLAGS:` from the override or the zigo
  archive/`-L -l` pair, then appends `system_ldflags` and a `#cgo darwin
  LDFLAGS:` framework line unconditionally.
- Static cgo archives do not contain system libraries, so the missing `-L` from
  pkg-config breaks links in non-default prefixes; dynamic mode already resolved
  them at Zig link time and the `-l` is redundant.
- `ZIGO012` rejects any pointer/slice field in an `extern struct`; there is no
  direction axis on types, only on parameters. Each generated opaque accessor
  takes `mu.RLock` and one native call.
- `classifyTypeChange` (`src/gen/abi_diff.zig:206`) returns `.breaking` for any
  value-struct field count change. Appending is directionally unsafe: a newer
  native writing a larger out struct into an older Go caller's buffer corrupts
  memory; only static cgo is lockstep.

## Target structure and invariants

- Link propagation is a documented table: pkg-config libraries → `#cgo
  pkg-config:`; plain system libraries → `-l`; `lib_paths` → `-L` (absolute
  paths allowed but flagged in docs as machine-specific); frameworks →
  `#cgo darwin LDFLAGS: -framework` with `-weak_framework` for weak; `rpaths`
  and `include_dirs` not propagated (documented). `cgo_flags` replaces the whole
  computed CFLAGS/LDFLAGS including system and framework lines, or the docs say
  precisely what survives — choose and implement one.
- Out-only value structs: `.repr = .value` with `.direction = .out_only` (name
  to be settled against the existing `Access` axis) permits `(ptr, len)` byte
  pairs and `(ptr, count)` arrays of eligible structs; such a struct may appear
  only as a return or error payload (never as a parameter or callback arg);
  the generated Go performs a recursive copy and, when the function is
  `.returns = .caller`, calls the plan-61 release afterwards. Field-pair
  recognition uses explicit metadata (`.fields = .{ .path = .{ .len = "path_len" } }`)
  rather than name heuristics.
- ABI append policy remains breaking by default.
