---
depends_on:
- "203-plugin-targets-and-native#2"
perf_phase: false
status: planned
---
> DONE-WHEN: Example 00 `zig build go-verify` and `go-purego-verify` plus `go test ./...` pass with `BuildInfo()` in use; example 13 `cargo test` passes with `build_info()`.
> NEXT: none

# Native-capable shipped plugin

## Planned Work

- New shipped plugin `plugins/buildinfo`: a Zig source exporting `build_info()` returning a static NUL-terminated string with Zig version, optimize mode and target triple; `native.symbols` declares `<prefix>_buildinfo_build_info` returning a C string; `go` slot renders `func BuildInfo() string` and `rust` slot renders `pub fn build_info() -> &'static str`, both calling the raw symbol through `Expr.rawCall`.
- Wire it into example 00 (Go, cgo and purego) and example 13 (Rust) with tests asserting the string is non-empty and contains the Zig version.
- Add generator goldens for both targets, a plugin unit test, `plugins/buildinfo/README.md`, and list it in `docs/plugins/README.md` and `docs/examples.md`.
- CHANGELOG "Plugin API 6.0" table completes; `docs/plugins/README.md` states that plugins may contribute native code and points at `buildinfo` as the reference.

## Done When

- Example 00 `zig build go-verify` and `go-purego-verify` plus `go test ./...` pass with `BuildInfo()` in use; example 13 `cargo test` passes with `build_info()`.
- Root `zig build test`, `plugins/*` tests, and every other example's `go-check` pass.
