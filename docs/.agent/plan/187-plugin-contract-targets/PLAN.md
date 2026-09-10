---
completed_at: "2026-09-10T03:51:54Z"
description: Make the plugin contract name and carry the output language, so a second target does not have to reinterpret Go-typed contract surface
plan_status: done
registered_at: "2026-09-10T03:29:16Z"
---
> NEXT: Rename the declaration-kind axis -- `plugin.Target` to `Subject`, ([Phase 0](phases/00-rename-subject-axis.md))

# Phases

- [x] [Phase 00: Free the word "target" inside the contract](phases/00-rename-subject-axis.md)
- [x] [Phase 01: Thread the resolved target through the contract](phases/01-thread-target.md)
- [x] [Phase 02: Rename the neutral contract surface off Go](phases/02-neutral-contract-names.md)

# Shared Verification

- `zig build test --summary all` at the repository root, every phase.
- `scripts/update-generator-cases.sh` then `git status --short tests/generator_cases`,
  which must be empty. The 74 cases exercise the plugin pipeline including the
  `plugin_api`, `plugin_json`, `plugin_satisfies`, `plugin_disabled` and
  `plugin_transform` cases, so a contract change that alters a rendered body
  shows up here rather than in review.
- Per example: `zig build test go-check go-lib abi-check go-coverage` then
  `(cd go && go test ./...)`, then `git status --short examples tests` empty.
- `zig fmt --check src build build.zig`.
- The whole plan is a rename-and-thread refactor. Any moved generated file is a
  behaviour change, not a formatting one; find the cause rather than re-blessing
  the snapshot.

# Decisions That Constrain Ordering

The word comes first. Phases 1 and 2 both have to say "target" constantly inside
`src/plugin.zig`, and until `plugin.Target` means something else that word is
ambiguous in exactly the file being edited -- the same collision plan 186 hit
when `const target = @import("target")` shadowed locals in three files. Phase 0
is also the one phase that provably cannot change behaviour, so it can be
verified by a clean snapshot alone.

Threading comes before renaming because it is the phase with real content: it
unblocks the two sites plan 186 had to leave on `targets.default` and it decides
how a target answers the file-shape question. Doing it while the surrounding
names are still the familiar Go ones keeps its diff about behaviour. The renames
then land last, over a contract whose semantics have stopped moving, which is
also what makes the 3.0 note in the changelog a single accurate list.

# Next Implementation Target

Rename the declaration-kind axis -- `plugin.Target` to `Subject`,
