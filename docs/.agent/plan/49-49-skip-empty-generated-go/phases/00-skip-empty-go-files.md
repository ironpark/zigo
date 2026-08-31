---
completed_at: "2026-08-31T18:45:46Z"
perf_phase: false
status: done
---

# Skip and prune declaration-free Go files

## Planned Work

- In `generator.zig`, classify a prepared `.go` file as declaration-free when
  its normalised content is exactly the marker line plus the `package` line.
- Skip writing it, and delete any file already at that path, ignoring
  `FileNotFound`.
- Update the camel-case generator test, which currently asserts all four public
  files exist and that three of them hold exactly the prelude: assert instead
  that the three are absent and the two that carry declarations are present.
- Delete the three `tests/generator_cases/scalar` golden files. The nine under
  `examples/` wait for phase 2, because regenerating an example needs the build
  changes.

## Done When

- `zig build test` and `zig build check` pass.
- The allocation-failure test, which pre-seeds every output path and then
  generates successfully, shows the three skipped paths gone afterwards. That
  is the stale-file removal.
- The generator-case golden comparison passes with the three `scalar` expected
  files deleted, proving generation no longer produces them.
- No surviving generated artifact changes content.
