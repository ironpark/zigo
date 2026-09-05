# SCOPE

- `src/gen/emit/emit.zig`, `raw.zig`, `cli.zig`, `generator.zig`,
  `src/main.zig`, `tests/generator_case_main.zig`, `build.zig`.
- `tests/generator_cases/scalar_multi_target`.
- `docs/configuration.md`, `CHANGELOG.md`.

# CONTEXT

## Current implementation and bottlenecks

`raw.zig` writes the link directives through `writeCgoLinkDirectives`, gated
by `ldflags_external`; the framework line follows unconditionally.

## Target structure and invariants

- `emit.Options.target_ldflags: []const TargetLdflags { constraint, flags }`.
  Written after the link directives and outside the `ldflags_external` gate.
- CLI flag `--target-ldflags "<goos>[,<goarch>]=<flags>"`, repeatable.
- `build.zig` `CgoFlags.target_ldflags: []const TargetLdflags` with
  `goos`, optional `goarch`, `ldflags` list; validated as platform words.
