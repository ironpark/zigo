---
completed_at: "2026-09-10T03:10:35Z"
depends_on:
- "186-186-target-interface#0"
perf_phase: false
status: done
---
> DONE-WHEN: `grep -rn 'target\.go\b\|target\.default' src build build.zig` returns only
> NEXT: none

# Thread the target as a value

## Planned Work

- Add `output_target: targets.Target` to `generator.Options`, defaulting to
  `targets.default` so the existing test call sites keep compiling.
  `src/main.zig` sets it explicitly through one `outputTarget()` function,
  which is the CLI's resolution point and the one place a `--target` flag
  would land.

  The field is `output_target`, not `target`: `Options` already carries
  `cgo_targets` and `target_ldflags`, which are build platforms.

  `emit.Options` does *not* get it. The plan said it would, but phase 0's
  ORDERING put `src/gen/emit/**` behind the seam, and handing the Go emitter a
  `Target` it would only ever be given Go for would contradict that. The value
  stops at `generator.zig`, which is the last layer in front of the seam.
- Take a `Target` in the validation entry points that production uses --
  `findIssueWithPlugins`, `findIssuesWithFacts`, `findIssuesConfigured`,
  `prepareDocument` -- and extend the `Rule` signature to carry it, so
  `names.zig`, `packages.zig`, `types.zig` and `functions.zig` receive the
  target instead of naming one. The short entry points `semanticDocument` and
  `findIssue` stay as Go-defaulted wrappers for the ninety-odd test call sites;
  they are the documented convenience layer, not a production path.
- Take a `Target` in `src/gen/report.zig` (as `Options.output_target`) and in
  `src/gen/abi_diff.zig` (as a new `diffForTarget`, with `diffWithBackends`
  kept as the Go-defaulted wrapper its tests call). The public surface a
  document projects is the target's rule, so the report on whether that
  surface broke is judged against the resolved target.
- `build.zig`'s `addGoBindings` is the second resolution point. It names
  `go_words` rather than a `Target`, which is the shape phase 0 already
  settled: a build script has no module graph, so it cannot import the file
  that imports `semantic`, and the two questions it asks -- is `go_package` an
  identifier, is the `raw_package` basename one -- are word-level rules that
  the leaf answers. No change was needed here in this phase.
- Leave `src/reflect/packages.zig` and `src/plugin/interfaces.zig` on
  `targets.default`, with a comment saying why. The reasons turned out to
  differ, and each comment says its own: the binding walk runs at comptime in
  the consumer's build, before the CLI has named a language, and
  `validate/packages.zig` asks the resolved target the same question at
  generate time; the plugin contract still declares its interfaces in Go's
  terms, so parameterizing its check would promise what the contract cannot
  keep. Record both in the phase 2 hand-off list.
- Thread the target through the rename-note helpers in `names.zig`
  (`functionRenameNoteAlloc`, `invalidTypeNameNoteAlloc`,
  `invalidMemberNameNoteAlloc`, `memberCollisionNoteAlloc`, `validGoNameAlloc`)
  as well. They were not in the plan, but each suggests a *valid* name to the
  user, which is the target's rule, and leaving them on the default would have
  left a diagnostic hint disagreeing with the rule that produced the
  diagnostic.

## Done When

- `grep -rn 'targets\.default\|targets\.go' src build build.zig` returns only
  the CLI resolution point, the two comptime pre-flights above, the
  Go-defaulted convenience wrappers in `validate.zig` and `abi_diff.zig` with
  the tests that call them, the two `Options` defaults, and `src/gen/emit/**`,
  which is behind the seam.
- Adding a target changes no call site in `src/gen/validate/**`,
  `src/gen/report.zig`, `src/gen/abi_diff.zig` or `src/gen/generator.zig`.
- Root `zig build test --summary all`, the thirteen examples, and a clean
  `scripts/update-generator-cases.sh` regeneration all pass.
