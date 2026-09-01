# GOALS

## Problem and the end result from the user's point of view

`zig build go-lib -Dtarget=x86_64-windows` fails on a POSIX host because
`addGoBindings` builds the whole reflection pipeline — `zigo-reflect`, the
bindings module, and the semantic module — for the *requested* target and
then executes the reflector on the host. Plan 56 guarded this with an
`isRunnableOnHost` panic and documented cross-compilation as a limitation.
After this plan, the reflection pipeline builds for the host
(`b.graph.host`) while the native library and generated shim build for
`-Dtarget`, so a macOS/Linux machine can produce a Windows DLL (and any
other supported target) with one command. Because reflection then observes
host-side type layouts, the generated shim gains compile-time ABI guards:
if a binding's extern-struct layout or scalar mapping would differ on the
actual target (e.g. `c_long` is 4 bytes on Windows, 8 on Linux), the target
compile fails loudly with a clear message instead of shipping a silently
mismatched ABI. CI proves the story end to end by running a Windows suite
against a DLL cross-built on Ubuntu — the leg dropped from plan 56.

## Measurable goals

- `zig build go-lib -Dtarget=<t>` succeeds from a POSIX host for all
  supported purego targets (linux/macos/windows × x86_64/aarch64); the
  `isRunnableOnHost` purego panic is removed.
- The generated Go tree is byte-identical whether produced natively or
  while cross-targeting (platform-independent output invariant), except
  for intended `--target-os` differences (ZIGO014 float-callback rejection
  on windows) which are target-, not host-, driven.
- The emitted shim contains comptime assertions pinning every
  extern-struct size and field offset (and any other reflected layout
  fact the ABI depends on) to the values reflection recorded; a fixture
  using a target-divergent type (e.g. `c_long`) demonstrates the guard
  failing for the divergent target with an actionable message and passing
  natively.
- CI: the Ubuntu job cross-builds one example's Windows DLL and hands it
  to the Windows job as an artifact; that example's purego suite passes
  against it.
- All existing suites stay green: `zig build test`/`check` (native and
  windows cross-`check`), ten cgo trees, four purego trees, Windows CI
  job unchanged in its native legs.

## Supported scope and non-goals

In scope: `build.zig` (`addGoBindings` module targeting, gate removal,
doctor target wiring), shim/ABI-guard emission in `src/gen/emit.zig` (and
`abi.zig`/reflect if layout capture needs extending), a test fixture for
the divergence guard, CI workflow, docs (`docs/purego.md`, limitations,
cross-compile recipe). Non-goals: supporting target-conditional binding
surfaces (comptime `builtin.target` branches that add/remove exports are
reflected for the host and documented as unsupported — the guards catch
layout divergence, not surface divergence), cgo-backend cross-compilation
to Windows (linking story is separate), non-64-bit targets, and Wine.

## Reference source / commit / license

Repository-local work on `main` (current HEAD after plan 56, commit
0d9ebf4). Prior art: plan 56 phase notes (the reflector blocker, the
five-line standalone cross-build of the committed shim, the PE
export-table listing procedure), `build.zig:550-676` (`addGoBindings`,
`isRunnableOnHost`, `doctor --target cross` which already exists).

## Completion criteria for the whole plan

All phases done; Ubuntu and Windows CI green including the cross-built
artifact leg; `planr overview` shows the plan complete.
