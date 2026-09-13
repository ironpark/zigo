---
depends_on:
- "201-api-consistency-refactor#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: A project calling both `addGoBindings` and `addRustBindings` with default step options builds without a duplicate-step panic.
> NEXT: none

# build.zig and CLI options

## Planned Work

- Rename standard steps `abi-check` → `go-abi-check` / `rust-abi-check`; make the generate step `go-<prefix>` rather than `<prefix>-go` when `name_prefix` is set (or drop `name_prefix` in favour of a `variant` name applied as suffix consistently).
- Move `library_loading` into a `Link.purego` payload so it is a type error under cgo.
- Replace CLI `--backend`/`--link-mode` (and `--base-backend`/`--current-backend`) with one `--link cgo-static|cgo-dynamic|purego`.
- Remove `Options.plugin_config`; `PluginModule.config` is the only plugin configuration path. Remove test-only `Options.plugins` from the public struct or expose it as `--plugins`.
- Remove `CgoFlags.ldflags` (replace policy); keep `extra_ldflags` and `target_ldflags`. Remove CLI `--pkg-config-libs` in favour of `--pkg-config-libs-file`.
- Group `go_module/go_package/go_package_path/raw_package` under a `layout` struct with an explicit `raw_colocated: bool`.
- Defaults: `bindings` defaults to `<module root dir>/bindings.zig`, `go_dir` to `b.path("go")`, `abi_base` to `"HEAD"`; `addStandardSteps` registers `-D<prefix>coverage-json` itself. Add `Options.standard_steps: ?StandardStepOptions = .{}` so the common case is one call.
- Namespace shared sidecars per language (`zigo/go/semantic.json`, `zigo/rust/semantic.json`, same for `errors.lock.json`); stop passing `--go-module` on the Rust path.
- Update all 14 example `build.zig` files and `docs/build-and-ship/*`, `docs/reference/build-options.md`.

## Done When

- A project calling both `addGoBindings` and `addRustBindings` with default step options builds without a duplicate-step panic.
- Example `build.zig` files carry no `coverage-json` option, no `bindings`, no `abi_base`.
- All example verify steps and `zig build test` pass.
