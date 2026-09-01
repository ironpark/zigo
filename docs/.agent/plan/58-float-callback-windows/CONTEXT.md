# SCOPE

Files expected to change: `src/gen/emit.zig` (purego shim callback
invoke, dispatcher emission, generated header typedefs for callback
function pointers), `src/gen/validate.zig` (+ tests) for ZIGO014,
whatever records the purego callback ABI version/compatibility, goldens
under `tests/`, regenerated purego trees (04, 05, 07, 08 — all four,
since the dispatcher/shim shape changes for every callback program, and
any cgo trees only if shared emission touches them — it should not),
`.github/workflows/ci.yml`, docs. Public Go API unchanged.

# CONTEXT

## Current implementation and bottlenecks

- Windows `syscall.NewCallback` (via purego) requires pointer-sized
  integer args and one pointer-sized result. Plan 56 fixed results
  (uniform `uintptr`, `callbackResult` helper) but left float params:
  generation rejects them for windows targets with ZIGO014
  (`validate.zig:32`), and CI asserts that rejection for 08.
- 08-telemetry-hub's dispatcher signature is
  `(uint64, float64, uint) int32`-shaped; its shim declares the Go
  callback pointer with a double parameter and calls it directly.
- The shim compiles per target (plan 57), but emitting different
  callback ABIs per target would break the identical-committed-tree
  invariant — hence uniform bits on all platforms.
- Plan 56 rejected this change when scoped as a hotfix because it is a
  breaking `_purego_v1` callback ABI change on every platform; as a
  dedicated plan, the ABI recording exists precisely to make such a
  change safe. The implementer must verify how the purego ABI hash/lock
  captures callback signatures and ensure the change surfaces there.
- purego *calls* with float args (RegisterFunc fn pointers like
  `fnTelemetryHubPush func(unsafe.Pointer, uint64, float64) int32`)
  work on POSIX and are purego-supported on Windows, but have never run
  in Windows CI because 08 was excluded entirely.

## Target structure and invariants

- Callback parameter lowering: f64 → u64 bits, f32 → u32 bits (zero-
  extended into the pointer-sized slot), on every platform. Shim invoke
  site: `@as(u64, @bitCast(value))` (and u32 for f32). Header typedef
  for the callback pointer uses the integer type with a comment naming
  the real type. Go dispatcher: `math.Float64frombits(uint64(arg))` /
  `math.Float32frombits(uint32(arg))` before invoking the user
  callback; user callback signatures unchanged.
- Non-float parameters keep their current lowering; results keep the
  plan-56 uniform `uintptr` shape.
- ZIGO014: remove if no rejection class remains for windows callback
  targets; if analysis finds one (e.g. a payload kind neither integer
  nor float), narrow the diagnostic text and tests to it. Either way
  the windows-target generation of 08 must succeed.
- CI: 08 rejoins the native Windows legs (build DLL, assert name, run
  suite); the ZIGO014 assertion is dropped/updated consistently. The
  cross-artifact leg (07) stays as is.
- POSIX fidelity tests live in an example suite (07 or 08) asserting
  bit-exact round trips through a callback: an ordinary value, negative
  zero, and +Inf at minimum.
