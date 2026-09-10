---
description: Map opaque handles to Drop, borrowed views to lifetimes, and caller-owned buffers to an owning slice with no copy
plan_status: in-progress
registered_at: "2026-09-10T05:36:17Z"
---
> NEXT: Separate the status channel from the declared error set, fixing the crate that ([Phase 0](phases/00-status-channel.md))

# Phases

- [x] [Phase 00: Separate the status channel from the declared error set](phases/00-status-channel.md)
- [x] [Phase 01: Move the constructor-name rule behind the target](phases/01-constructor-name-rule.md)
- [x] [Phase 02: Opaque handles become owning structs with Drop](phases/02-handles-as-drop.md)
- [x] [Phase 03: Borrowed views carry the lifetime they borrow](phases/03-borrowed-views.md)
- [x] [Phase 04: Caller-owned buffers are owned, not copied](phases/04-owned-buffers.md)
- [ ] [Phase 05: Prove it in the example, and hand it on](phases/05-example-and-handoff.md)

# Shared Verification

Run every phase, not just the last:

- `zig build test --summary all` at the repository root. The root build has no
  `go-check`, `abi-check` or `go-coverage` step -- those live in each example's
  build, so the fuller run is per example.
- `scripts/update-generator-cases.sh` then
  `git status --short tests/generator_cases`, which must be empty apart from a
  case the phase deliberately added. `<case>/semantic.json` is the *input* and
  the sibling `expected/` tree is the golden.
- Per Go example:
  `(cd examples/<name> && zig build test go-check go-lib abi-check go-coverage)`
  then `(cd examples/<name>/go && go test ./...)`. Thirteen of them.
- The Rust example takes its own list: `zig build test rust-check rust-lib
  abi-check rust-coverage`, then `cargo test`, `cargo clippy --all-targets --
  -D warnings`, `cargo fmt --check`.
- `git status --short examples tests` empty afterwards.
- `zig fmt --check src build build.zig`.
- Every new golden crate compiles through the build's own
  `rustc --edition 2021 -D warnings` step, which is where "generated text no
  compiler has seen" gets caught.

Traps this plan expects, all of them previously real:

- **A promoted empty error set is not the same thing as no status channel.**
  This plan exists partly because those were conflated. Any new branch that
  tests `origin.@"return" == .error_union` must say which of the two questions
  it is asking.
- **`plugins/` and `tests/plugins/` write against the contract directly.**
  Grepping only `src` misses them; that broke example 10 once. Plugins do not
  run for a Rust target (`output_targets` defaults to Go), but a rename in
  `targets.zig` still reaches them.
- **`abi-check` reads its baseline with `git show <ref>:zigo/semantic.json`,**
  so a document written by an earlier commit on this branch must still parse.
  This plan adds no IR field and changes no key, so the class of failure that
  broke plan 185 should not arise; if a phase finds itself wanting to move a
  key, stop and re-plan.
- **A brand-new example cannot pass `abi-check` before its first commit,**
  because the baseline does not exist yet. Plan 188 hit this. The example here
  already exists, so only its `semantic.json` changing matters.
- The macOS `ld` version-mismatch warning predates this work and is unrelated.
- `planr phase done` fails on uncommitted changes. Commit first; do not
  `--force`. Delete any `.planr-*` scratch file before finishing a phase.

# Decisions That Constrain Ordering

Phase 0 comes first because everything after it walks into the bug it fixes. A
handle receiver is *the* reason `promoteCheckedFunctions` exists, so every
method this plan emits has a status channel and an empty declared error set --
precisely the shape that produces an uncompilable crate today. Fixing it while
the only affected input is a narrow-integer parameter means the fix is verified
on the smallest possible case, and the concept it introduces is then available
to phase 2 rather than being invented inside it.

Phase 1 comes second because it is the only phase whose success criterion is
the pure absence of change. Moving the `New{s}` literal behind the target while
Rust still has no constructors means an empty golden diff proves the move is
faithful; doing it inside phase 2 would leave any movement ambiguous between
"the rule moved wrongly" and "handles changed something they should not have".
This is the argument plans 185, 186 and 188 all used for their own first phase,
and it worked each time.

Phases 2, 3 and 4 are ordered by dependency, and each is a different kind of
failure. Phase 2's mistakes are `rustc` errors about ownership. Phase 3's are
about lifetimes and are invisible to a compile check that only compiles valid
code -- hence its compile-fail check. Phase 4's are about memory that is freed
twice or not at all, which only a running test finds. Fusing them would put
three unlike failure modes behind one green tick.

Phase 5 is last because it is the only phase that cannot be verified by
generated text: it needs a linker, `cargo`, and a process that runs. It is also
the phase most likely to have to shrink, so it is arranged so that a failure
there leaves phases 0 through 4 standing as a tested backend.

Every phase carries the full generator-case and example verification rather
than deferring it, because plan 185's breakage was a mid-branch commit
producing a document a later commit could not parse -- a class of bug only
per-phase verification catches.

# Next Implementation Target

Separate the status channel from the declared error set, fixing the crate that
