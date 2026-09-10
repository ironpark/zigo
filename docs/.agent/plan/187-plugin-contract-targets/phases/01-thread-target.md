---
depends_on:
- "187-plugin-contract-targets#0"
perf_phase: false
status: planned
---
> DONE-WHEN: No `targets.default` reference remains in `src/plugin/**` or
> NEXT: none

# Thread the resolved target through the contract

## Planned Work

- Give `plugin.Options` the resolved `targets.Target` and expose it on
  `Context`, `ArtifactContext`, `ValidateContext`, `TransformContext` and
  `AnalyzeContext`, so a plugin reads the same value the generator resolved.
- Add the file-shape members `ZIGO059` needs to `targets.Target`: the source
  extension is already there, so this is the test-file rule. Shape it as an
  optional, so a language whose tests are not a filename convention answers
  "none" instead of being pushed into Go's shape.
- Rewrite the `ZIGO059` file-shape branch in `src/gen/generator.zig` against
  those members, dropping the literal `".go"` and `"_test.go"`, and reword its
  hint so it does not name Go.
- Point the interface-name check in `src/plugin/interfaces.zig` and the
  package-directory fallback in `plugin.publicFilePathAlloc` (which calls
  `naming.snakeAlloc` directly) at the threaded target, and delete the comments
  that explain why they could not.
- Add `Plugin.output_targets`, defaulting to `&.{"go"}`, and skip a plugin whose
  list excludes the resolved target's `name`. Cover the skip with a test.
- Bump `plugin.contract_version` to `3.0`.

## Done When

- No `targets.default` reference remains in `src/plugin/**` or
  `src/gen/generator.zig`.
- `ZIGO059`'s file-shape branch contains no Go literal, and its existing
  diagnostic tests still fail the same inputs.
- A test shows a plugin with a non-matching `output_targets` contributing
  nothing: no diagnostic, no output file.
- `zig build test --summary all` passes, generator cases regenerate clean, and
  every example passes its full check with no output moved.
