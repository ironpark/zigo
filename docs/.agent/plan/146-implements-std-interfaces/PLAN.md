---
description: Function-level .implements opt-in that adds io.Writer/io.Reader/io.WriterTo/io.ReaderFrom conformance wrappers to handle methods
plan_status: in-progress
registered_at: "2026-09-07T07:54:46Z"
---
> NEXT: Add the `.implements` key to the declaration DSL, reflect it, and carry it in semantic.json. ([Phase 0](phases/00-declare-reflect-ir.md))

# Phases

- [ ] [Phase 00: Declaration, reflection, IR](phases/00-declare-reflect-ir.md)
- [ ] [Phase 01: Validation ZIGO058](phases/01-validate-shape.md)
- [ ] [Phase 02: Emission and golden cases](phases/02-emit-wrappers.md)
- [ ] [Phase 03: Example 11, docs, changelog](phases/03-example-docs.md)

# Shared Verification

- `zig build test` (full) after each phase; `-Dtest-filter=implements` for fast loops.
- `scripts/update-generator-cases.sh implements_std implements_std_purego`, then review
  the `expected/` diff by hand.
- `zig build go` / `zig build purego-go` in `examples/11-io-streams` and
  `go test ./...` in `go/` and `go-purego/`.
- Regenerate examples 03, 04, 07, 08, 10, 12 and confirm `git status --short examples`
  shows no drift.

# Decisions That Constrain Ordering

0 → 1 → 2 → 3. Phase 1 and 2 could overlap on the emitter skeleton, but goldens must
be generated only after validation exists so a bad-shape case cannot slip into `expected/`.

# Next Implementation Target

Add the `.implements` key to the declaration DSL, reflect it, and carry it in semantic.json.
