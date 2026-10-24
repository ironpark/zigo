---
description: Migrate zigo, its build integration, plugins, examples and CI from Zig 0.16 to Zig 0.17
plan_status: in-progress
registered_at: "2026-10-24T11:40:10Z"
---
> NEXT: Port the build script to the 0.17 configure model. ([Phase 0](phases/00-build-configure-model.md))

# Phases

- [x] [Phase 00: Build script on the 0.17 configure model](phases/00-build-configure-model.md)
- [x] [Phase 01: Language and std changes in src and tests](phases/01-language-and-std.md)
- [ ] [Phase 02: Examples, plugins and fixtures](phases/02-examples-plugins.md)
- [ ] [Phase 03: Version bump, CI and docs](phases/03-version-ci-docs.md)

# Shared Verification

`zig build test` at the root, plus the per-example and per-plugin builds that
CI runs, all on Zig 0.17.0.

# Decisions That Constrain Ordering

The build script has to configure before anything else can compile, so it
comes first. Then src, then the consumers, then metadata.

# Next Implementation Target

Port the build script to the 0.17 configure model.
