---
description: Move Go-specific fields in the semantic IR under a target namespace so a second output language can be added
plan_status: in-progress
registered_at: "2026-09-09T09:41:31Z"
---
> NEXT: Add the missing Go field accessors and convert every reader in `src/gen` and ([Phase 0](phases/00-read-through-accessors.md))

# Phases

- [x] [Phase 00: Route Go field reads through accessors](phases/00-read-through-accessors.md)
- [ ] [Phase 01: Nest the fields and migrate the document](phases/01-nest-and-migrate.md)
- [ ] [Phase 02: Move the Go standard-library features](phases/02-move-plugin-go-features.md)

# Shared Verification

- `zig build test --summary all` at the repository root, for every phase. The
  root build has no `go-check` or `abi-check` step; those live in each example's
  build, so the fuller run is per example:
  `cd examples/<name> && zig build test go-check go-lib abi-check go-coverage`
  followed by `(cd go && go test ./...)`. Phases 1 and 2 run it for every
  example, which is what proves the moved document still drives an identical
  Go surface.
- `scripts/update-generator-cases.sh` followed by
  `git status --short tests/generator_cases`, which must be empty. The 74 cases
  keep their version-1 `semantic.json` inputs, so a clean regeneration means 70
  old documents still parse into exactly the program they parsed into before.
  Any file appearing in that diff means a read was missed.
- A unit test in `tests/ir.zig` parsing a version-1 fixture and asserting it
  serializes identically to its version-2 spelling, and that a version-1
  document with no Go-specific field gains no `go` object.

# Decisions That Constrain Ordering

Reads move first because converting every reader to an accessor while the fields
stay put is verifiable with zero snapshot churn: if `zig build test` passes and
no snapshot moved, the reader set is provably complete. The field move then has
one seam to change instead of dozens, and any snapshot diff it produces is
attributable to the move alone.

`iterator` and `implements` are held back to phase 2 because they are owned by
built-in plugins and compared by `abi_diff`, so they carry risk the plain data
fields do not. Splitting them keeps phase 1's diff explainable as pure renaming.

# Next Implementation Target

Add the missing Go field accessors and convert every reader in `src/gen` and
