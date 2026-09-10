---
completed_at: "2026-09-10T03:20:29Z"
depends_on:
- "186-186-target-interface#1"
perf_phase: false
status: done
---
> DONE-WHEN: `grep -rn '_gen\.go' src/gen/emit src/gen/generator.zig` finds only the
> NEXT: none

# Move file layout and the formatter behind the target

## Planned Work

- Give `Target` the generated-source file rule: `source_extension`,
  `generated_suffix`, `generatedFileNameAlloc(stem)` producing `<stem>_gen.go`,
  and `isSource(path)`. Repoint the eight `_gen.go` literals in
  `src/gen/emit/emit.zig` and the manifest-kind classification in
  `src/gen/generator.zig`. Emit keeps composing the stem; the target turns a
  stem into a file name.

  The predicate is `isSource`, not `isGeneratedSource`: what it decides is
  whether a path is a source file in the output language, which is a different
  question from whether this generator wrote it. The remaining `.go` tests in
  `src/gen/generator.zig` belong to the plugin contract -- the `ZIGO059` rule
  reads `plugin.GoFileKind` and compares against `goFilePathAlloc` -- so they
  stay, and are recorded in the hand-off list.
- Move the gofmt knowledge out of `src/main.zig`: `formatGeneratedGo` becomes
  `formatGenerated`, driven by `target.formatter` for the executable, the
  leading arguments, the override-flag text and the install hint. A target with
  no formatter returns instead of being special-cased.

  `cli.Generate.gofmt_executable` becomes `formatter_executable: ?[]const u8`,
  where null means the target's default. The `--gofmt` flag keeps its name: it
  is user-visible surface, which this plan's constraints put out of scope.
  `cli.Doctor.gofmt_executable` also keeps its name, because `zigo doctor`
  probes the Go toolchain specifically and belongs to the tooling blocker.
- Write the hand-off into `PLAN.md`: a `What a Rust Target Implements`
  section giving every `Target` member with what Rust would answer, and what
  is still not behind the seam -- the plugin contract's Go-typed API and the
  two pre-flights it holds, `sync_check.zig`, the `--gofmt` flag and `doctor`,
  the Go initialism table inside `pascalAlloc`/`camelAlloc`, and cancellation.
  The table also records the one interface change adding Rust would ask for:
  `exportedNameAlloc` has to split into a type rule and a function rule,
  because Rust exports types in PascalCase and functions in snake_case.
- Update `docs/.agent/research/rust-target-feasibility.md`: mark step 2 of the
  recommended order done and correct blocker 5.

## Done When

- `grep -rn '_gen\.go' src/gen/emit src/gen/generator.zig` finds only doc
  comments and test expectations, no path construction.
- `src/main.zig` names `gofmt` only where it forwards the CLI's doctor
  options, which probe the Go toolchain on purpose.
- `PLAN.md` carries the `What a Rust Target Implements` section, and
  `docs/.agent/research/rust-target-feasibility.md` shows step 2 of its
  recommended order complete and blocker 5 resolved.
- Root `zig build test --summary all`, the thirteen examples, and a clean
  `scripts/update-generator-cases.sh` regeneration all pass.
