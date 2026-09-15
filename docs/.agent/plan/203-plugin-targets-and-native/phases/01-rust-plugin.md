---
completed_at: "2026-09-15T01:45:04Z"
depends_on:
- "203-plugin-targets-and-native#0"
perf_phase: false
status: done
---
> DONE-WHEN: `cd examples/13-rust-quick-start && zig build rust-verify-equivalent steps && cargo test` pass with the enumkit-generated Rust in use.
> NEXT: none

# Rust-capable shipped plugin

## Planned Work

- Give `plugins/enumkit` a `rust` slot rendering the same feature set it renders for Go (`values()`, `is_known()`, and `Display`/`FromStr` where the Go side has `String`/parse) through `rustbuild`.
- Extend example 13 (`13-rust-quick-start`) with an enum that uses `enumkit`, a Rust test exercising the generated items, and a matching Go use if the example also has a Go tree (it does not; keep it Rust-only).
- Add a Rust golden under `tests/generator_cases/` for the enumkit Rust output, and a plugin unit test using `plugin.testing` for Rust.
- Docs: `docs/plugins/authoring.md` gains a section on rendering for two targets from one plugin; `plugins/enumkit/README.md` lists Rust output.

## Done When

- `cd examples/13-rust-quick-start && zig build rust-verify-equivalent steps && cargo test` pass with the enumkit-generated Rust in use.
- `plugins/enumkit` `zig build test` covers both targets.
