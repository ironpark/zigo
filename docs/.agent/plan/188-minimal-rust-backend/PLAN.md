---
description: Add a minimal Rust target covering scalars, slices and error unions, mirroring examples/00-quick-start
plan_status: in-progress
registered_at: "2026-09-10T04:02:52Z"
---
> NEXT: Split `exportedNameAlloc` into a type rule and a function rule, with Go ([Phase 0](phases/00-split-exported-name-rule.md))

# Phases

- [x] [Phase 00: Split the exported-name rule into a type rule and a function rule](phases/00-split-exported-name-rule.md)
- [x] [Phase 01: Give Rust a Target value and an IR namespace](phases/01-rust-target-value.md)
- [x] [Phase 02: Name the neutral emitters and write the Rust emitter](phases/02-rust-emitter.md)
- [x] [Phase 03: Select the target from the command line](phases/03-cli-target-flag.md)
- [ ] [Phase 04: Build integration and a runnable example](phases/04-runnable-example.md)

# Shared Verification

Run every phase, not just the last:

- `zig build test --summary all` at the repository root. The root build has no
  `go-check`, `abi-check` or `go-coverage` step -- those live in each example's
  build, so the fuller run is per example. `CONTRIBUTING.md` is easy to misread
  on this point.
- `scripts/update-generator-cases.sh` then
  `git status --short tests/generator_cases`, which must be empty. Note that
  `<case>/semantic.json` is the *input* and the goldens are the sibling
  `expected/` tree. 70 of the 74 cases carry `ir_version` 1, so every run is
  also an IR migration regression suite.
- Per example, over all of them:
  `(cd examples/<name> && zig build test go-check go-lib abi-check go-coverage --summary all)`
  then `(cd examples/<name>/go && go test ./...)`.
- `git status --short examples tests` empty afterwards.
- `zig fmt --check src build build.zig`.
- From phase 2 on, `rustc --edition 2021 --crate-type lib` over every generated
  Rust golden. From phase 4, `cargo test` and the demo, actually run.

Traps this plan expects to hit, all of them previously real:

- `plugins/` (enumkit, json, satisfies) and `tests/plugins/` write against the
  contract directly. Grepping only `src` misses them, which broke example 10
  once. Plan 187 made `output_targets` default to Go, so a Rust target should
  simply skip them -- confirm that rather than assume it.
- `abi-check` reads its baseline through `git show <ref>:zigo/semantic.json`, so
  a document written by an *earlier commit on this branch* must still parse.
  This plan avoids the class of failure by never moving an IR key; if a phase
  wants to, stop and re-plan.
- The macOS `ld` version-mismatch warning predates this work and is unrelated.
- `planr phase done` fails on uncommitted changes. Commit first; do not
  `--force`. Delete any `.planr-*` scratch file before finishing a phase.

# Decisions That Constrain Ordering

The interface change comes first because it is the only phase whose success
criterion is pure absence of change. Splitting `exportedNameAlloc` while Go is
still the only target means an empty golden diff proves the split is faithful --
exactly the argument plan 186 used for its own phase 0, and the reason plans 185
and 186 both front-loaded their seam moves. Doing it later, alongside a second
target, would leave any golden movement ambiguous between "the split was wrong"
and "Rust changed something it should not have".

The target value comes before the emitter because the emitter is written against
it. Splitting them also separates two different kinds of failure: a wrong
keyword table is a unit-test failure in phase 1, while a wrong signature is a
`rustc` failure in phase 2. Fused, both would surface as the same broken golden.

The emitter comes before the CLI flag because a `--target rust` that resolves to
a target with no emitter is a flag that cannot be tested. With the emitter in
place, phase 3's test is a real generation.

Build integration and the example come last because they are the only phase
that cannot be verified by generated text alone -- it needs a linker, `cargo`
and a running binary. It is also the phase most likely to have to shrink, so it
is arranged so that a failure there leaves phases 0 through 3 standing as a
usable, tested Rust target reachable from the CLI.

Every phase carries the full generator-case and example verification rather than
deferring it, because plan 185's breakage was a mid-branch commit producing a
document a later commit could not parse -- a class of bug only per-phase
verification catches.

# Next Implementation Target

Split `exportedNameAlloc` into a type rule and a function rule, with Go
