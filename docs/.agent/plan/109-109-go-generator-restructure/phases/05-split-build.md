---
completed_at: "2026-09-05T07:24:10Z"
perf_phase: false
status: done
---
> DONE-WHEN: `build.zig` is under 1,000 lines.
> NEXT: none

# build.zig consumer API only

## Planned Work

- Move `addProcessContractTests`, `addPkgConfigContractTests`,
  `addGeneratorCases`, `addGoldenArtifactChecks`, `hasCaseFile`,
  `matchesAnyFilter` and the `build()` test/check/snapshot wiring into
  `build/tests.zig`; move `GeneratorModules`, `createGeneratorModules`,
  `addGenerator*` into `build/modules.zig`.
- `build.zig` keeps `Options`, `GoBindings`, `addGoBindings`, the link input
  and publish steps, and a short `build()` that delegates.

## Done When

- `build.zig` is under 1,000 lines.
- `zig build test`, `zig build check`, and the fixture projects under
  `tests/fixtures` build unchanged.
