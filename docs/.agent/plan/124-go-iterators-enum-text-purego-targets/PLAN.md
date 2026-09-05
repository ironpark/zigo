---
completed_at: "2026-09-05T21:26:37Z"
description: Go iter.Seq wrappers for optional-returning iterator methods, opt-in enum text encoding, and purego multi-target library layout
plan_status: done
registered_at: "2026-09-05T21:10:05Z"
---
> NEXT: Enum text encoding: `.text = true` registration, emission, case, example, docs. ([Phase 0](phases/00-enum-text.md))

# Phases

- [x] [Phase 00: Enum text encoding](phases/00-enum-text.md)
- [x] [Phase 01: Iterator wrappers](phases/01-iterators.md)
- [x] [Phase 02: purego targets](phases/02-purego-targets.md)

# Shared Verification

- `zig build test --summary all` after every phase.
- Touched examples: `zig build test go-check abi-check go-coverage --summary all`,
  `zig build go`, `(cd go && go test -count=1 ./...)`, and for purego examples
  `zig build purego-go purego-go-verify` with `CGO_ENABLED=0 go test`.
- `git status --short` shows no unintended generated changes.

# Decisions That Constrain Ordering

Phases are independent; run 0, 1, 2 in that order so the generator cases and
docs land incrementally. Each phase commits separately.

# Next Implementation Target

Enum text encoding: `.text = true` registration, emission, case, example, docs.
