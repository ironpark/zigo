---
description: Breaking refactor of zigo's public surface (DSL, build.zig/CLI, generated Go, plugin API) for usability and consistency
plan_status: in-progress
registered_at: "2026-09-13T18:43:12Z"
---
> NEXT: Docs, comments, dead code: risk-free cleanup that establishes the baseline for the renames. ([Phase 0](phases/00-docs-and-dead-code.md))

# Phases

- [x] [Phase 00: Docs, comments, dead code](phases/00-docs-and-dead-code.md)
- [ ] [Phase 01: build.zig and CLI options](phases/01-build-options.md)
- [ ] [Phase 02: DSL naming and single spellings](phases/02-dsl-consistency.md)
- [ ] [Phase 03: Generated Go conventions](phases/03-generated-go.md)
- [ ] [Phase 04: Plugin API surface](phases/04-plugin-api.md)

# Shared Verification

After every phase: `zig build test` at repo root; for each example `zig build go-verify` (and the
`purego-` prefixed variant where present) and `go test ./...`; `plugins/*` `zig build test`. CHANGELOG
"breaking" section updated with old → new tables in the same phase that renames.

# Decisions That Constrain Ordering

0 → 1 → 2 → 3 → 4. Phases touch overlapping files, so they run strictly sequentially, each in its own
handoff agent, committed before the next starts.

# Next Implementation Target

Docs, comments, dead code: risk-free cleanup that establishes the baseline for the renames.
