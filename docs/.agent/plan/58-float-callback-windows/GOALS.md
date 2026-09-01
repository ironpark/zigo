# GOALS

## Problem and the end result from the user's point of view

Plan 56 made purego callback dispatchers Windows-compatible for results
(uniform `uintptr`), but float *parameters* remained impossible: Windows
`syscall.NewCallback` rejects float args, so generation refuses
windows-target programs with float-carrying callbacks via ZIGO014, and
08-telemetry-hub is excluded from the Windows CI job. The fix plan 56
deferred is the principled one: pass float callback parameters as their
IEEE-754 bit patterns through integer registers, uniformly on every
platform. The Zig shim (compiled per target) `@bitCast`s f32/f64 to
u32/u64 before invoking the Go callback pointer; the Go dispatcher
receives `uintptr` and rebuilds the float with `math.Float64frombits` /
`math.Float32frombits` before calling the user's typed Go callback. One
ABI shape everywhere keeps the committed generated tree identical across
hosts. After this plan ZIGO014 is retired (no remaining rejection class,
or narrowed to whatever genuinely stays unsupported), 08-telemetry-hub
generates for Windows, rejoins the Windows CI job, and its suite passing
there also gives the first Windows runtime proof of float arguments in
purego *calls* (SetThreshold etc.), which were never exercised on
Windows because the whole example was excluded.

## Measurable goals

- Generation for `--target-os windows` succeeds for float-parameter
  callbacks; ZIGO014 is removed (or, if analysis finds a residual
  genuinely-unsupported shape, narrowed to it with updated tests and
  docs — decision recorded).
- The purego callback ABI passes f32/f64 parameters as u32/u64 bits on
  ALL platforms: shim-side `@bitCast` at the invoke site, Go-side
  `math.Float*frombits` in the dispatcher; user-facing Go callback types
  keep natural float parameters (no public API change).
- The committed generated trees remain identical regardless of host;
  POSIX suites prove float round-trip fidelity through the new path
  (exact bit-pattern round trip including negative zero and an
  infinity, plus an ordinary value).
- 08-telemetry-hub returns to the `purego-windows` CI job (native leg);
  the ZIGO014-rejection assertion in CI is removed or updated to match
  the retired/narrowed diagnostic.
- ABI versioning handled deliberately: the callback ABI change is
  reflected wherever zigo records ABI compatibility (abi-check /
  abi_diff / lock files) so a stale library plus regenerated Go (or
  vice versa) fails loudly rather than corrupting floats — the
  implementer verifies which mechanism covers this and records it.
- `zig build test`/`check` (native + windows cross-check) green; ten
  cgo + four purego trees green; Windows CI green with 08 restored.

## Supported scope and non-goals

In scope: purego callback emission in `src/gen/emit.zig` (shim invoke
site, dispatcher bodies, header callback typedefs), ZIGO014 in
`src/gen/validate.zig` and its tests, ABI recording, goldens,
regeneration, CI workflow, docs (limitations, purego docs). Non-goals:
the cgo backend's callback path (cgo trampolines already handle floats
natively on POSIX; cgo-Windows remains unsupported), float *results*
from callbacks (rejected already at a different layer or nonexistent —
verify and document rather than change), struct-typed callback payloads,
and any change to purego *call* marshalling (RegisterFunc float args are
purego's own responsibility and already work).

## Reference source / commit / license

Repository-local work on `main` (HEAD after plan 57, commit c4285f0).
References: plan 56 phase 5 notes (compileCallback constraints read from
Go's `runtime/syscall_windows.go`: args nothing wider than a pointer, no
floats outside 386; exactly one pointer-sized result), the uniform-
uintptr-result dispatcher shape and its `callbackResult` helper, and
Go's `math.Float64bits`/`Float64frombits` contract. Prior CI loop
pattern from plans 56–57.

## Completion criteria for the whole plan

All phases done; Windows CI green with 08-telemetry-hub in the native
job; POSIX float-fidelity tests green; `planr overview` complete.
