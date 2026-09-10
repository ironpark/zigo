---
completed_at: "2026-09-10T03:45:10Z"
depends_on:
- "187-plugin-contract-targets#0"
perf_phase: false
status: done
---
> DONE-WHEN: No `targets.default` reference remains in `src/plugin/**` or
> NEXT: none

# Thread the resolved target through the contract

## Planned Work

- Give `plugin.Options` the resolved `targets.Target`. `Context` and
  `ArtifactContext` carry `options`, so they expose it as a method for free;
  `ValidateContext` and `TransformContext` carry no options, so they take the
  value as a field; `AnalyzeContext` delegates to the `Context` it wraps.
  `emit.Options` is an alias of `plugin.Options`, so the field is reachable
  from emit -- it is carried there, not read there, and what keeps that honest
  is `Plugin.output_targets` rather than a comment.
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

- No site in `src/plugin/**` or `src/gen/generator.zig` *reaches for*
  `targets.default` in place of a threaded value. The name still appears as the
  default of the new `target` fields and as an argument in unit tests, which is
  what a default is for; what goes away is the interface-name check and the
  package-directory fallback resolving the language behind the caller's back.
- `ZIGO059`'s file-shape branch contains no Go literal, and its existing
  diagnostic tests still fail the same inputs. Its message and the
  interface-name diagnostic interpolate `display_name`, so their Go text stays
  byte-identical and only a non-Go target changes it.
- A test shows a plugin with a non-matching `output_targets` contributing
  nothing: no diagnostic, no output file.
- `zig build test --summary all` passes, generator cases regenerate clean, and
  every example passes its full check with no output moved.
