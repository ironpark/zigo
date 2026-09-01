# GOALS

## Problem and the end result from the user's point of view

zigo currently supports macOS and Linux only. The purego backend hard-blocks
Windows in `build_options.puregoTargetSupported`, the generated
`DefaultLibraryName` map has no `windows` entry, and the generated loader
calls `purego.Dlopen`, which is POSIX-only. The cgo backend is untested on
Windows and CI runs on Ubuntu alone. Yet the ingredients are cheap: purego
v0.10.2 itself supports Windows (including callback trampolines), and Zig
cross-compiles the shared library with a `-Dtarget` flag. After this plan a
Windows user consumes zigo bindings through the purego backend: the
generator emits a build-tagged Windows loader, the DLL name resolves by
default, doctor passes on windows/amd64 and windows/arm64, a Windows CI job
proves it stays working, and the docs describe the cross-compile story
(build the DLL on any host with Zig; `GOOS=windows go build` needs no C
toolchain). Native-Windows cgo remains out of scope.

## Measurable goals

- Generated purego packages compile and run on windows/amd64: a build-tagged
  loader (`syscall.LoadLibrary`/`GetProcAddress` or purego's Windows
  facilities) behind `//go:build windows`, with the existing Dlopen path
  behind `//go:build !windows`; identical exported surface (`LoadLibrary`,
  `DefaultLibraryName`, error shapes) on both.
- `DefaultLibraryName` resolves to `<name>_zigo.dll` on Windows (no `lib`
  prefix), `lib<name>_zigo.dylib`/`.so` unchanged elsewhere.
- `puregoTargetSupported` accepts windows on x86_64/aarch64; doctor reports
  PASS on Windows and its unsupported message no longer claims macOS/Linux
  only.
- CI gains a `windows-latest` job that builds the example DLLs with Zig and
  runs the purego example test suites (`CGO_ENABLED=0`); the existing Ubuntu
  jobs are unchanged.
- Cross-compile documentation: building a Windows DLL from macOS/Linux via
  `zig build go-lib -Dtarget=x86_64-windows`, shipping it next to a
  `GOOS=windows` pure-Go binary; a CI or test step proves the cross-built
  DLL loads on the Windows job.
- `zig build test` and the existing fourteen example trees stay green on
  Linux/macOS.

## Supported scope and non-goals

In scope: purego loader emission in `src/gen/emit.zig` (file split by build
tags if needed), `src/build_options.zig` platform gate, `src/gen/doctor.zig`
probe/messages, `.github/workflows/ci.yml`, goldens, regeneration of purego
trees, and docs (`docs/bindings.md`, limitations, READMEs). Non-goals:
native-Windows cgo backend support (mingw linking — future work), 32-bit or
non-amd64/arm64 targets, changing the library-loading policy semantics
(explicit/automatic axes stay as designed in plan 33), and any POSIX
behavior change.

## Reference source / commit / license

Repository-local work on `main` (starting at 0691ab6). References:
ebitengine/purego v0.10.2 Windows support (`NewCallback`, syscall-based
loading on Windows), Go `syscall`/`golang.org/x/sys/windows` LoadLibrary
conventions, Zig `-Dtarget` cross-compilation. Prior plans: 33
(library-loading policy), 45 (ubuntu-only CI — deliberately reduced; this
plan partially reverses it with justification), 47 (platform link fixes).

## Completion criteria for the whole plan

All phases done; Ubuntu CI green as before plus a green Windows job running
the purego suites against both natively-built and cross-built DLLs;
`planr overview` shows the plan complete.
