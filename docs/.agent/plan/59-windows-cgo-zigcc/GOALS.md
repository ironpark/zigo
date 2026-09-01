# GOALS

## Problem and the end result from the user's point of view

The cgo backend (static archive linked into the Go binary — single-file
deployment, no DLL) works on macOS/Linux only. On Windows, cgo requires a
gcc-compatible C toolchain, conventionally mingw-w64. zigo users already
have Zig installed, and `zig cc` is a gcc-compatible clang driver that
ships its own mingw-w64 headers and CRT — so `CC="zig cc"` can plausibly
give Windows cgo with zero extra toolchain. That combination is
community-proven for Go in general but unvalidated for zigo's generated
output (static `.a` link via `#cgo LDFLAGS`, callback trampolines through
`cgo.Handle`, panic bridging). After this plan, either (a) the cgo
backend builds and passes its suites on windows-latest with
`CC="zig cc"` and no mingw, proven in CI, with the recipe documented and
doctor aware of zig-as-CC — or (b) the spike surfaces a hard blocker,
which gets documented precisely (what fails, why, upstream issue links)
and the plan records the honest verdict instead of forcing it. The spike
phase decides which; the plan is explicitly allowed to conclude
"documented as unsupported" if the blocker is real.

## Measurable goals

- Spike verdict recorded in phase notes with reproducible commands: for
  at least examples 01-scalar (no callbacks) and 07-event-queue
  (callbacks), `CGO_ENABLED=1 CC="zig cc -target x86_64-windows-gnu"
  GOOS=windows go test -c ./...` (build-only) from this POSIX host
  either produces test executables or fails with diagnosed causes.
- If the spike succeeds: a `cgo-windows` CI job runs at least two cgo
  example suites natively on windows-latest with `CC="zig cc"` and
  `CGO_ENABLED=1`, green; cross-built test executables from the Ubuntu
  job optionally run on the Windows job as an artifact leg if the spike
  shows it works cheaply.
- Any generator/build-integration changes needed (LDFLAGS shape, archive
  vs import-lib naming, doctor's C-compiler probe accepting `zig cc`,
  cgo cross-target doctor state) land via the generator, with goldens,
  and keep all existing suites green.
- 04-callback stays excluded wherever system zlib is unavailable
  (consistent with the purego job's existing exclusion note).
- POSIX behavior unchanged: `zig build test`/`check`, ten cgo trees,
  four purego trees all green throughout.
- Docs: a copy-pasteable Windows cgo recipe (native and, if proven,
  cross), replacing the "unvalidated future work" hedge from plan 56 —
  or a precise unsupported-status entry if the spike fails.

## Supported scope and non-goals

In scope: a time-boxed build spike, whatever emission/build.zig/doctor
changes the spike shows are needed, CI, docs. Non-goals: MSVC ABI
support (zig cc targets the gnu ABI; `-target *-windows-msvc` for cgo
is out), 386/arm32 targets, changing the cgo backend's design (link
model, cgo.Handle usage), Windows-specific cgo features beyond parity
with POSIX, and fixing upstream Go/Zig bugs (document + link instead).

## Reference source / commit / license

Repository-local work on `main` (HEAD after plan 58, commit 4e50a51).
References: community practice of `CC="zig cc -target <triple>"` for
cgo cross-compilation (Go issue tracker and Zig docs discuss known
sharp edges: response-file handling, `-mthreads`-style flags cgo may
pass, unsupported flag warnings needing `-Wl` passthrough); zigo's
generated `#cgo` block (`raw_gen.go`: `CFLAGS: -I.../zig-out/include`,
`LDFLAGS: .../lib<name>_zigo.a` + system libs); plan 47 (linux cgo
layout/link fixes) as precedent that per-OS link work is normal; plans
56–58 CI loop.

## Completion criteria for the whole plan

Spike verdict recorded; if positive, Windows cgo CI green and docs
updated; if negative, blockers documented and docs state the status
precisely; `planr overview` complete either way.
