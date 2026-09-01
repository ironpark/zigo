# SCOPE

Files expected to change: `build.zig` (reflector/bindings/semantic module
targets → `b.graph.host`; purego host gate removed; doctor target flag
already handles cross), `src/gen/emit.zig` (comptime guard emission into
the shim), possibly `src/reflect/*` and `src/gen/ir/abi.zig` if reflected
layout facts need to be carried explicitly for the guards, `tests/`
fixtures and goldens, `.github/workflows/ci.yml`, docs. Generated shim
text changes (guards added) for every example; generated Go must not
change at all.

# CONTEXT

## Current implementation and bottlenecks

- `build.zig:576-602`: `zigo-gen` already builds for `b.graph.host`, but
  `semantic_module`, `bindings_module`, and the `zigo-reflect` executable
  build for `options.target`; `b.addRunArtifact(reflector)` then executes
  it on the host — impossible for a foreign target.
- `build.zig:560-567`: purego backend panics unless
  `isRunnableOnHost(target, host)`; comment says "Reflection runs the
  bindings module as an executable, so generation needs a target the host
  can execute."
- `build.zig:676`: doctor already receives `--target cross` when the
  target is not host-runnable, so a cross doctor path exists.
- `semantic.json` records extern-struct layouts (`"layout": "extern"`)
  observed at reflection time. All supported targets are 64-bit
  little-endian, so fixed-width ints, floats, and pointers agree — but
  C-variable types (`c_long`, `c_ulong`: 4 bytes on Windows, 8 on
  Linux/macOS; `c_longdouble`, etc.) genuinely diverge, and user bindings
  may use them in extern structs or scalar positions.
- Plan 56 phase 6 proved the committed shim cross-builds standalone and
  established a PE export-listing procedure (recorded in its phase notes).

## Target structure and invariants

- Reflection pipeline (semantic module, bindings module, reflector) builds
  for `b.graph.host`; library, shim compile, and header install build for
  `options.target`. The user's module is compiled twice (host for
  reflection, target for the library) — same as zigo-gen already is.
- The emitted shim gains a `comptime` block per reflected extern struct:
  `@sizeOf` and per-field `@offsetOf` asserts against the reflected
  numbers, with `@compileError`-grade messages naming the struct, field,
  expected and actual values, and the likely cause (target-divergent C
  types). Scalar positions using target-divergent C types should be
  either guarded the same way or rejected at generation with a
  diagnostic — investigate which layer sees them and choose; record the
  decision. Guards are emitted unconditionally (native builds prove them
  trivially true, keeping one code path).
- The purego platform gate (`puregoTargetSupported`) still applies to the
  *target*; the host requirement disappears.
- Doctor keeps reporting `cross` targets as today; no doctor behavior
  change beyond what the gate removal exposes.
- CI artifact leg: Ubuntu cross-builds `-Dtarget=x86_64-windows` for one
  callback-free-or-callback-bearing example that the Windows job already
  runs (prefer 07-event-queue for callback coverage), uploads
  `zig-out/bin/<stem>.dll`, and the Windows job runs that example's suite
  with `ZIGO_TEST_LIBRARY` pointing at the artifact. Keep added CI time
  modest.
