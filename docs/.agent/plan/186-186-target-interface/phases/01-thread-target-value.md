---
depends_on:
- "186-186-target-interface#0"
perf_phase: false
status: planned
---
> DONE-WHEN: `grep -rn 'target\.go\b\|target\.default' src build build.zig` returns only
> NEXT: none

# Thread the target as a value

## Planned Work

- Add `target: Target` to `generator.Options` and `emit.Options`, and give the
  generator option a `target.default` default so the existing test call sites
  keep compiling. `src/main.zig` sets it explicitly; that is one of the two
  resolution points.
- Take a `Target` in the validation entry points that production uses --
  `findIssueWithPlugins`, `findIssuesWithFacts`, `findIssuesConfigured`,
  `prepareDocument` -- and extend the `Rule` signature to carry it, so
  `names.zig`, `packages.zig`, `types.zig` and `functions.zig` receive the
  target instead of naming one. The short entry points `semanticDocument` and
  `findIssue` stay as Go-defaulted wrappers for the ninety-odd test call sites;
  they are the documented convenience layer, not a production path.
- Take a `Target` in `src/gen/report.zig` and `src/gen/abi_diff.zig` rather
  than naming one.
- Make `build.zig`'s `addGoBindings` the second resolution point: it names
  `target.go` once, because the entry point is Go's by name.
- Leave `src/reflect/packages.zig` and `src/plugin/interfaces.zig` on
  `target.default`, with a comment saying why: both run at comptime in a
  consumer's build, where no target has been selected yet, and both checks are
  re-run authoritatively by `validate/packages.zig` and the plugin contract at
  generate time. Record them in the phase 2 hand-off list.

## Done When

- `grep -rn 'target\.go\b\|target\.default' src build build.zig` returns only
  the two resolution points, the two comptime pre-flights above, the
  Go-defaulted validation wrappers, and `target.zig` itself.
- Adding a target changes no call site in `src/gen/validate/**`,
  `src/gen/report.zig`, `src/gen/abi_diff.zig` or `src/gen/generator.zig`.
- Root `zig build test --summary all`, the thirteen examples, and a clean
  `scripts/update-generator-cases.sh` regeneration all pass.
