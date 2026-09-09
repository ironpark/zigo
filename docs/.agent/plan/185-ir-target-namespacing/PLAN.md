---
description: Move Go-specific fields in the semantic IR under a target namespace so a second output language can be added
plan_status: in-progress
registered_at: "2026-09-09T09:41:31Z"
---
> NEXT: Add the missing Go field accessors and convert every reader in `src/gen` and ([Phase 0](phases/00-read-through-accessors.md))

# Phases

- [ ] [Phase 00: Route Go field reads through accessors](phases/00-read-through-accessors.md)
- [ ] [Phase 01: Nest the fields and migrate the document](phases/01-nest-and-migrate.md)
- [ ] [Phase 02: Move the Go standard-library features](phases/02-move-plugin-go-features.md)

# Shared Verification

- `zig build test --summary all` for every phase.
- `zig build test go-check abi-check go-coverage --summary all` for phases 1 and 2,
  which is what proves the moved document still drives an identical Go surface.
- `scripts/update-generator-cases.sh` followed by `git status --short tests/generator_cases`:
  the regenerated tree must differ only in `semantic.json`. A generated `.go`,
  `.zig` or `.h` file appearing in that diff means a read was missed.
- A dedicated unit test in `src/gen/ir/semantic.zig` parsing a version-1 fixture
  and asserting it equals the version-2 document.

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
