---
description: Extract a Target interface so the output language's keyword, naming, layout and formatter rules live in one place
plan_status: in-progress
registered_at: "2026-09-10T02:48:46Z"
---
> NEXT: Add `src/gen/target.zig` and `src/gen/target/go.zig`, wire the module, and move the Go rules out of `naming.zig` and `semantic.zig` with every caller repointed. ([Phase 0](phases/00-introduce-target-seam.md))

# Phases

- [x] [Phase 00: Introduce the Target seam with Go behind it](phases/00-introduce-target-seam.md)
- [ ] [Phase 01: Thread the target as a value](phases/01-thread-target-value.md)
- [ ] [Phase 02: Move file layout and the formatter behind the target](phases/02-layout-and-formatter.md)

# Shared Verification

- `zig build test --summary all` at the repository root, every phase. The root
  build has no `go-check`, `abi-check` or `go-coverage` step -- those are
  defined in each example's build, so the fuller run is per example:
  `cd examples/<name> && zig build test go-check go-lib abi-check go-coverage`
  then `(cd go && go test ./...)`, over all thirteen.
- `scripts/update-generator-cases.sh` followed by
  `git status --short tests/generator_cases`, which must be empty, every phase.
  The 74 cases regenerate the whole Go, shim and header surface from checked-in
  documents, so an empty diff is the plan's central pass criterion: a rule that
  changed while moving, or a caller left on a deleted path with a subtly
  different fallback, shows up as a moved golden file.
- `git status --short` over `examples/*/zigo` and `examples/*/go` after the
  example runs, which must also be empty: `go-check` regenerates into the
  committed tree, so any drift in `semantic.json` or generated Go appears there.
- `git diff --stat` at the end of each phase must show no generated artifact.
- The `grep` assertions in each phase's Done When, which are what turn "the
  rules are gathered" from a claim into a check.

# Decisions That Constrain Ordering

The seam comes before the threading, for the reason plan 185 proved: moving
rules while every caller still resolves the target locally is verifiable with
zero snapshot churn, so a green phase 0 is evidence that the caller set is
complete. Threading then has a known set of signatures to change instead of a
search, and any failure in phase 1 is a compile error rather than a silent
change of behaviour.

`src/gen/emit/**` stays on the target's side of the seam throughout. The whole
tree exists to write Go, was measured at 0% reuse for a second language, and
would be replaced wholesale by a Rust emitter rather than parameterized. Making
its 59 `pascalAlloc` calls go through a `Target` would enlarge the diff by an
order of magnitude and would say something false: that a Rust backend reuses
those code paths. The seam is placed where reuse actually stops.

File layout and the formatter come last because they are the only parts that
touch the output tree's shape and the process the CLI runs. Keeping them in
their own phase means that if a golden file does move, the phase boundary says
whether a naming rule or a layout rule moved it.

Phase 0 leaves no intermediate document shape: nothing in this plan changes
`semantic.json`, so unlike plan 185 the phase boundaries cannot produce a
document that a later commit fails to parse. `abi-check` reading
`git show <ref>:zigo/semantic.json` therefore stays valid at every commit.

# Next Implementation Target

Add `src/gen/target.zig` and `src/gen/target/go.zig`, wire the module, and move the Go rules out of `naming.zig` and `semantic.zig` with every caller repointed.
