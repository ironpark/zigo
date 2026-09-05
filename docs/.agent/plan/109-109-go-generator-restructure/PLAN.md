---
description: "Restructure the Go generator: split emit and validate, move shared decisions into lowering, and separate build.zig consumer API from test wiring"
plan_status: in-progress
registered_at: "2026-09-05T06:56:05Z"
---
> NEXT: Split emit.zig into `src/gen/emit/` by output file with goldens unchanged. ([Phase 0](phases/00-split-emit.md))

# Phases

- [ ] [Phase 00: Split emit.zig by output file](phases/00-split-emit.md)
- [ ] [Phase 01: One Must-variant rule in lowering](phases/01-must-variant-rule.md)
- [ ] [Phase 02: Helper references from rendered text](phases/02-helpers-by-render.md)
- [ ] [Phase 03: Materialized layouts by index](phases/03-materialized-index.md)
- [ ] [Phase 04: Split validate.zig into an ordered rule list](phases/04-split-validate.md)
- [ ] [Phase 05: build.zig consumer API only](phases/05-split-build.md)
- [ ] [Phase 06: Reflect scans each source once](phases/06-reflect-single-scan.md)
- [ ] [Phase 07: Document the layout](phases/07-document-layout.md)

# Shared Verification

- After every phase: `zig fmt --check src build.zig build`, `zig build check`,
  `zig build test`.
- Golden invariance: `git status --short tests/generator_cases` is empty after
  `zig build test`; the generator cases compare output byte-for-byte.
- Phase 1 adds a validate unit test; phase 6 adds a scan-count test.
- Phase 5 additionally runs `zig build lib` and `zig build go` inside
  `tests/fixtures/*` through the existing contract tests.

# Decisions That Constrain Ordering

Phase 0 first: every later emit change lands in the split files. Phases 1, 2, 3
depend only on phase 0 and can run in any order. Phase 4 follows phase 1 so the
Must-variant check is already on the lowered program when validate is split.
Phases 5 and 6 are independent. Phase 7 last.

# Next Implementation Target

Split emit.zig into `src/gen/emit/` by output file with goldens unchanged.
