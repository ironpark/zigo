---
depends_on:
- "186-186-target-interface#1"
perf_phase: false
status: planned
---
> DONE-WHEN: `grep -rn '_gen\.go' src/gen/emit src/gen/generator.zig` finds only the
> NEXT: none

# Move file layout and the formatter behind the target

## Planned Work

- Give `Target` the generated-source file rule: `source_extension`,
  `generated_suffix`, `generatedFileNameAlloc(stem)` producing
  `<stem>_gen.go`, and `isGeneratedSource(path)`. Repoint the `_gen.go`
  literals in `src/gen/emit/emit.zig` and the `.go` suffix tests that classify
  manifest entries in `src/gen/generator.zig`. Emit keeps composing the stem;
  the target turns a stem into a file name.
- Move the gofmt knowledge out of `src/main.zig`: `formatGeneratedGo` becomes
  `formatGenerated`, driven by `target.formatter` for the executable, the
  leading arguments, the override-flag text and the install hint. A target with
  no formatter skips the step instead of special-casing Go.
- Write the hand-off into the plan: a `## What a Rust target implements`
  section listing every `Target` member with what Rust would answer, and the
  three things that are still not behind the seam -- the plugin contract's
  Go-typed API, the two comptime pre-flights from phase 1, and the Go
  initialism table inside `pascalAlloc`/`camelAlloc`.
- Update `docs/.agent/research/rust-target-feasibility.md`: mark step 2 of the
  recommended order done and correct blocker 5.

## Done When

- `grep -rn '_gen\.go' src/gen/emit src/gen/generator.zig` finds only the
  target's own rule and test expectations.
- `src/main.zig` contains no occurrence of `gofmt`.
- The plan carries the `What a Rust target implements` section, and the
  research document's recommended order shows step 2 complete.
- Root `zig build test --summary all`, the thirteen examples, and a clean
  `scripts/update-generator-cases.sh` regeneration all pass.
