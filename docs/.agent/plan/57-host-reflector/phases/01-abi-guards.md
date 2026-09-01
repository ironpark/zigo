---
depends_on:
- "57-host-reflector#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Guards present in every regenerated shim; the divergence fixture fails
> NEXT: none

# Comptime ABI guards in the shim

## Planned Work

- Extend reflection/ABI capture if needed so the generator knows every
  extern struct's reflected size and field offsets; emit a comptime
  assert block into the shim pinning them, with messages naming struct,
  field, expected/actual, and the target-divergent-C-type hint.
- Decide and implement handling for target-divergent C scalar types in
  non-struct positions (guard or generation-time diagnostic); record the
  decision in the phase notes.
- Add a test fixture using `c_long` in an extern struct: native build
  passes; `-Dtarget=x86_64-windows` fails with the guard message
  (assert via the build-failure fixture machinery like the ZIGO007 test).
- Update shim goldens for all examples; regenerate; generated Go
  unchanged.

## Done When

- Guards present in every regenerated shim; the divergence fixture fails
  for windows and passes natively; `zig build test` green; no Go drift.

## Notes

- Reflection/ABI capture needed no extension. `lower.zig` already computes
  every `extern struct`'s size, alignment and field offsets from the semantic
  IR, and `renderValueStructShim` already emitted `@sizeOf`/`@alignOf`/
  `@offsetOf` asserts against them. The real gap was the message: a failing
  `std.debug.assert` reports "reached unreachable code" and names nothing.
- Replaced those asserts with an emitted `zigoAbiGuard` helper that raises
  `@compileError(std.fmt.comptimePrint(...))`. It names the checked fact
  (`@offsetOf(Config, "ratio")`), the target's value, the reflected value, and
  the target-divergent-C-type cause. The helper is emitted whenever the shim
  mirrors at least one struct, so there is one code path and native builds
  prove the guards trivially.
- Decision on target-divergent C scalars in NON-struct positions: no new
  machinery, because there is no silent-corruption vector to close. Verified
  by cross-compiling a scratch fixture to `x86_64-windows-gnu`:
  - Parameter position (`fn takes(v: c_long)`) already fails the target
    compile loudly, at the exact shim line, with Zig's own
    `error: expected type 'c_long', found 'i64'` plus
    `note: signed 32-bit int cannot represent all possible signed 64-bit
    values`. That names the divergent type better than a synthesized
    diagnostic would.
  - Callback parameters fail the same way: the trampoline's reflected
    signature does not coerce to the target's function-pointer type.
  - Return position and tagged-union snapshot payloads compile, because
    `c_long` -> `i64` is a lossless implicit widening that the shim performs
    at the boundary. Go then reads an `int64` holding the correct value, so
    the wider mirror is a surface difference, not a mismatch.
  - The one case where bytes must be reproduced rather than converted is a
    struct's memory layout, and that is exactly what the guards pin.
  A generation-time diagnostic was rejected: the generator sees only the
  reflected widths and `--target-os`, never the host/target comparison, so it
  could not tell divergence from agreement without new plumbing that buys
  nothing over the two outcomes above.
- Fixture: `tests/fixtures/abi-divergence`, a purego binding over
  `Sizes = extern struct { span: c_long, tail: u32 }`. Two legs registered on
  the `test` step, following the ZIGO007 `invalid-project` pattern: `zig build
  lib` must succeed, and `zig build lib -Dtarget=x86_64-windows-gnu` must exit
  1 with `zigo ABI guard: @sizeOf(Sizes) is 8 on this target, but zigo
  reflected 16 on the build host.` The pair is skipped on a Windows host,
  where nothing diverges. (Field named `span`, not `signed`: `signed` is a C
  keyword and breaks the generated header.)
- Goldens: only `tests/generator_cases/value_struct/expected/shim.zig`
  changed, updated through the case runner plus `zig build snapshot
  -- <expected> <actual> --update-snapshots`, never by hand.
- Green: `zig fmt --check`, `zig build check` (native, x86_64- and
  aarch64-windows-gnu), `zig build test`, ten cgo trees, four purego trees and
  their `CGO_ENABLED=0` Go suites. `git status -- examples` empty, so the
  generated Go is unchanged: the guards live only in the shim.
