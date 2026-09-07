---
description: "Plugin frame for the generator: typed extension options, method/type/file hooks, build-time registry; built-ins migrated onto it and an external showcase plugin"
plan_status: in-progress
registered_at: "2026-09-07T09:09:09Z"
---
> NEXT: Define the plugin contract and put the hook calls into the public emitters. ([Phase 0](phases/00-contract-and-hooks.md))

# Phases

- [x] [Phase 00: Contract and hook points](phases/00-contract-and-hooks.md)
- [x] [Phase 01: Typed extension transport and validation](phases/01-ext-transport.md)
- [x] [Phase 02: Migrate built-ins onto the frame](phases/02-migrate-builtins.md)
- [x] [Phase 03: External plugins: build wiring and cases](phases/03-external-loading.md)
- [ ] [Phase 04: Showcase plugins](phases/04-showcase.md)

# Shared Verification

- Per phase: `zig build test`, `scripts/update-generator-cases.sh` (no updates until phase 4),
  regenerate every example and confirm `git status --short examples` is empty.
- Phase 3: build example 11 with a plugin path that does not compile and confirm the
  error names the plugin module.
- Phase 4: example Go tests on cgo and purego; `staticcheck -checks U1000`.

# Decisions That Constrain Ordering

0 → 1 → 2 → 3 → 4. Phase 2 can start its first move (iterator) as soon as phase 0 lands,
since it does not need `ext`; the rest of 2 waits for 1 only for `Context.options`.

# Next Implementation Target

Define the plugin contract and put the hook calls into the public emitters.
