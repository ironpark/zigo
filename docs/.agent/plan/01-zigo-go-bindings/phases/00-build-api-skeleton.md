---
completed_at: "2026-08-29T04:06:51Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build` and `zig build test` succeed at the repository root.
> NEXT: none

# Build API skeleton and test harness

## Planned Work

- Rewrite `build.zig` as zigo's public API: expose module `zigo`, build the `zigo-gen`
  executable, declare the `test` step, and export
  `pub fn addGoBindings(b, Options) GoBindings`.
- Define `Options` (name, module, bindings, go_dir, go_module, target, optimize, prefix,
  link_mode, cgo_flags, abi_base) and `GoBindings` (update, check, abi_check, lib,
  semantic_json) per `docs/01-architecture.md` section 5. Stub the step bodies.
- Create `examples/01-scalar/` as a Zig library plus Go module that depends on zigo by
  relative path and calls `addGoBindings`, so the API has a real consumer immediately.
- Define the diagnostic type: severity, code, message, declaration site, hint; render to
  stderr and exit non-zero.
- Build the snapshot harness: directory-tree comparison with a readable diff and an
  `--update-snapshots` mode, under `tests/`.

## Done When

- `zig build` and `zig build test` succeed at the repository root.
- `cd examples/01-scalar && zig build go` resolves zigo as a dependency and runs the
  stubbed steps without error.
- The snapshot harness detects an intentionally corrupted golden tree and prints which
  files differ.
