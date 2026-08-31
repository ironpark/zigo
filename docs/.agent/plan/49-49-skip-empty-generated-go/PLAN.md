---
description: Do not write a generated Go file that declares nothing, and remove one left by an earlier run
plan_status: in-progress
registered_at: "2026-08-31T18:35:59Z"
---
> NEXT: Skip writing a Go file that declares nothing, remove a stale one, and delete the twelve existing empties. ([Phase 0](phases/00-skip-empty-go-files.md))

# Phases

- [x] [Phase 00: Skip and prune declaration-free Go files](phases/00-skip-empty-go-files.md)
- [ ] [Phase 01: Generation formats its own Go output](phases/01-generation-formats-its-own-go-output.md)
- [ ] [Phase 02: Publishing copies whatever generation produced](phases/02-publish-generated-go-tree.md)

# Shared Verification

- `zig build test`, `zig build check`.
- The generator-case golden comparison passes with the three `scalar` expected
  files deleted, proving generation no longer produces them.
- `git diff --stat` shows deletions and the generator change only: no surviving
  generated file changes content.

# Decisions That Constrain Ordering

One phase: the code change and the artifact deletion have to land together or
the golden comparison fails in between.

# Next Implementation Target

Skip writing a Go file that declares nothing, remove a stale one, and delete the twelve existing empties.
