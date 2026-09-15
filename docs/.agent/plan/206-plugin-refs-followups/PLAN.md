---
depends_on:
- plugin-refs-and-capabilities
description: "Close plan 205 follow-ups: authoring-typed refs on field and tag use, and json enum decoding through the generated Parse<Type> when text is on"
plan_status: in-progress
registered_at: "2026-09-15T10:07:00Z"
---
> NEXT: Field and tag use with authoring refs. ([Phase 0](phases/00-field-tag-refs.md))

# Phases

- [ ] [Phase 00: Field and tag use with authoring refs](phases/00-field-tag-refs.md)
- [ ] [Phase 01: json decodes through Parse<Type>](phases/01-json-parse.md)

# Shared Verification

Per phase: `zig fmt --check .`; root `zig build test`; every `plugins/*` `zig build test`; examples 07, 10, 11
`go-verify` (+ purego) and `go test ./...`; example 13 `rust-check` and `cargo test`; `go-check` elsewhere.

# Decisions That Constrain Ordering

0 → 1, sequential, one handoff agent per phase, committed before the next.

# Next Implementation Target

Field and tag use with authoring refs.
