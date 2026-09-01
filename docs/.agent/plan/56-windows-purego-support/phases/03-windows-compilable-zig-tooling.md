---
completed_at: "2026-09-01T15:39:15Z"
depends_on:
- "56-windows-purego-support#1"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build check -Dtarget=x86_64-windows-gnu` compiles every artifact with
> NEXT: none

# Windows-compilable Zig tooling

## Planned Work

- The first `purego-windows` CI run failed before any Go suite: zigo's own Zig
  tooling does not compile for Windows. `src/gen/doctor.zig` calls
  `std.DynLib.open`, and Zig 0.16's `std/dynamic_library.zig` has no Windows
  branch -- `InnerType` falls through to a struct whose `open` is
  `@compileError("unsupported platform")` and which has no `close`, so
  `DynLib.close` fails too. Two compile errors kill every step that builds
  `zigo-gen` or the doctor test.
- Replace the direct `std.DynLib` use with a small portable helper that keeps
  the loadability probe working on all three systems: delegate to
  `std.DynLib` on POSIX and call `LoadLibraryW`/`FreeLibrary`/`GetProcAddress`
  through kernel32 on Windows. No new dependency, and the probe still reports
  `missing` and `unloadable` distinctly. `tests/shared_library_smoke.zig` uses
  `std.DynLib` the same way and gets the same treatment.
- Decide what the `purego-windows` job should run: audit which `zig build`
  steps the workflow invokes on Windows, keep the ones that are meaningful
  there, and justify the selection in the workflow comment.

## Done When

- `zig build check -Dtarget=x86_64-windows-gnu` compiles every artifact with
  no errors, which is the compile-level proof available without a Windows
  machine.
- `zig build test` stays green on the POSIX dev host with doctor coverage
  unchanged, and POSIX probe behaviour is byte-identical.

## Notes

- Root cause confirmed locally with `zig build check -Dtarget=x86_64-windows-gnu`,
  which reproduced both errors exactly as CI reported them: `@compileError`
  from `DynLib.InnerType`'s fallthrough arm and the missing `inner.close()`.
  Naming `std.DynLib` is enough to fail the build, so gating the *call* would
  not have been sufficient.
- Option (a) from the direction was taken: `src/dynamic_library.zig` delegates
  to `std.DynLib` on POSIX and declares `LoadLibraryW`/`FreeLibrary`/
  `GetProcAddress` as kernel32 externs on Windows. `std.os.windows` declares no
  loader entry points in 0.16, so they are named locally; no new dependency.
  The loadability probe therefore still works on Windows and still separates
  `missing` from `unloadable`, mapping FILE_NOT_FOUND / PATH_NOT_FOUND /
  MOD_NOT_FOUND to `error.FileNotFound`.
- `tests/shared_library_smoke.zig` was the only other `std.DynLib` user (grep
  over `src` and `tests`) and now shares the helper. It stays POSIX-run but is
  wired into `check` so it cannot silently stop compiling for Windows.
- CI decision: the Windows job runs `zig build check`, not `zig build test`.
  `check` compiles every artifact and is precisely the regression class that
  broke the first run, while `test` would additionally run the cgo generation
  fixture (`tests/fixtures/invalid-project` shells out to a nested
  `zig build go`) and the Go-based godoc audit -- cgo paths this plan does not
  support on Windows, whose failures would be noise. Test behaviour is
  platform-independent and stays on Ubuntu; what is Windows-specific is that
  the tooling compiles (`check`) and that the loader really loads a DLL (the
  Go suites and `go-doctor` inside `purego-go-verify`).
- The Ubuntu job now also runs `zig build check` for x86_64- and
  aarch64-windows-gnu, so the next Windows-only compile break is caught on the
  cheap runner instead of costing a Windows job.
- Compile-level proof: `zig build check` passes for x86_64/aarch64 x gnu/msvc.
  Windows runtime behaviour remains unproven until the CI job runs.
