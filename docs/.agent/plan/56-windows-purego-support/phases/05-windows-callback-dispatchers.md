---
completed_at: "2026-09-01T16:25:59Z"
depends_on:
- "56-windows-purego-support#4"
perf_phase: false
status: done
---
> DONE-WHEN: No generated dispatcher violates `compileCallback`'s result rule; a payload
> NEXT: none

# Windows-compatible purego callback dispatchers

## Planned Work

- `purego.NewCallback` panics at load time on Windows: it is a thin wrapper
  over `syscall.NewCallback`, whose `compileCallback` demands exactly one
  result of exactly pointer size. The generated dispatchers return `int32` or
  nothing at all, so every callback-carrying purego package dies on Windows.
- Make every dispatcher return `uintptr` on every platform, converting inside
  the body, so a void-result callback still returns a value and an `int32`
  result is truncated back to its low word by the C caller. Uniform on all
  systems, so the committed tree stays identical across hosts.
- Audit every callback payload against `compileCallback`'s other rules and
  handle what cannot be satisfied with a clear diagnostic rather than an
  opaque panic from inside purego.
- Update goldens, regenerate the purego trees, and adjust the Windows CI job
  to whatever set of examples it can legitimately cover.

## Done When

- No generated dispatcher violates `compileCallback`'s result rule; a payload
  that cannot work on Windows is rejected at generation time with a zigo
  diagnostic naming the function.
- `zig build test`, `check`, the Windows cross `check`s, the POSIX purego
  suites, and `GOOS=windows` vet/build all pass on the dev host.

## Notes

- Read the constraints out of Go's runtime rather than guessing.
  `runtime.compileCallback` panics unless the function has exactly one result
  of exactly `goarch.PtrSize`, and the panic string is the one CI reported.
  `abiDesc.assignArg` separately rejects any argument larger than a pointer
  and, on anything but 386, any float32/float64 argument. Sub-word integer
  arguments are fine, so `int32` parameters were never the problem -- the
  result was.
- Decision, results: option (a), uniform `uintptr` on every platform. Build
  tags were rejected here because the shape is legal everywhere: purego's
  POSIX trampolines accept a wider result, the native side declares the
  callback as returning `int32_t` and reads only the low word, and both
  supported architectures return in EAX/W0 within RAX/X0. So one shape works
  everywhere and the committed tree stays identical across hosts, which the
  build-tagged loader files already cost us once.
  A void-result callback now returns 0, and the `-3`/`-4` failure codes go
  through an emitted `callbackResult(int32) uintptr` helper, since a negative
  typed constant cannot be converted to `uintptr` inline.
- Decision, float parameters: no Go-side fix exists. Marshalling the bits
  would have to happen on the Zig side, and the purego callback ABI passes a
  bare C function pointer with no room for a stateful adapter, so it would
  mean reintroducing generated trampolines that plan 31 deliberately removed
  for this backend -- a breaking change to the `_purego_v1` ABI on every
  platform, disproportionate here. Generation therefore refuses with ZIGO014
  when the target is Windows, naming the function and pointing at the integer
  bit pattern. Refusing at generation time is honest: the tree is
  platform-independent, so the check keys off the target the caller asked for
  and POSIX users are unaffected.
- Plumbing for that: a `--target-os` flag on `zigo-gen generate`, which
  `build.zig` fills from `options.target.result.os.tag`.
- Audit of every generated dispatcher: 04-callback `(int32, uint) int32`,
  07-event-queue `(uint64, int32, uint) int32`, 08-telemetry-hub
  `(uint64, float64, uint) int32`. Only the last carries a float, and only it
  is rejected. No callback returns a float or takes an argument wider than a
  pointer.
- CI: 08-telemetry-hub leaves the Windows job, which now asserts the ZIGO014
  rejection instead of quietly skipping it, and 10-tagged-union's
  wrong-library slot moves to the event-queue DLL. Windows loader-policy
  coverage drops to the explicit loader; the automatic internal loader stays
  covered on Ubuntu only.
- POSIX runtime proof of the widening: 07-event-queue's suite asserts panic
  translation, so `callbackResult(-3)` demonstrably round-trips through the C
  ABI and reaches the native side as -3.
