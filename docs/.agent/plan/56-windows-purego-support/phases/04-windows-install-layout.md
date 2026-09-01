---
completed_at: "2026-09-01T15:57:22Z"
depends_on:
- "56-windows-purego-support#3"
perf_phase: false
status: done
---
> DONE-WHEN: Nothing computes the installed shared-library path from a hardcoded install
> NEXT: none

# Windows install layout for the shared library

## Planned Work

- `purego-go-doctor` fails on Windows with "is missing" for a DLL the same run
  installed successfully. Zig installs a shared library to `bin`, not `lib`, on
  Windows: `InstallArtifact.Options.dest_dir` resolves `.lib` artifacts as
  `if (artifact.isDll()) .bin else .lib`, and only the import library goes to
  `lib`. zigo hardcodes `.lib` when it builds the doctor's `--library`
  argument and `GoBindings.library_filename`.
- Make the installed path come from the `InstallArtifact` step itself
  (`dest_dir` + `dest_sub_path`) instead of a hardcoded directory and a
  hand-rolled filename, so the convention cannot drift from Zig's again.
  Expose the resolved path on `GoBindings` so consumers need not guess.
- Sweep the remaining `zig-out/lib` assumptions: the purego example loader
  tests that build a default path, `08-telemetry-hub`'s `search_paths` policy,
  the Windows CI job's artifact assertions and `ZIGO_TEST_LIBRARY` values, and
  the packaging docs.

## Done When

- Nothing computes the installed shared-library path from a hardcoded install
  directory; POSIX paths are unchanged.
- `zig build test`, `zig build check`, the Windows cross `check`s, and the
  fourteen Go example trees stay green on the dev host.

## Notes

- Confirmed in Zig's own source: `std/Build/Step/InstallArtifact.zig` resolves
  a library's default `dest_dir` as `.exe, .@"test" => .bin` and
  `.lib => if (artifact.isDll()) .bin else .lib`, with `isDll()` meaning
  dynamic linkage on a windows target. The import library goes to `implib_dir`,
  which is why `lib` looked plausible but held the wrong file.
- Reproduced the path computation without needing a Windows machine or the
  blocked cross-build: a throwaway `build.zig` that creates a dynamic library
  and prints `b.getInstallPath(install.dest_dir.?, install.dest_sub_path)` for
  each target reported `lib/libprobe_zigo.dylib` (macOS),
  `lib/libprobe_zigo.so` (linux), and `bin/probe_zigo.dll` (windows). That is
  the exact expression zigo now uses, so POSIX output is unchanged and Windows
  is corrected.
- Single source of truth: `installedLibraryPath` reads `dest_dir` and
  `dest_sub_path` back off the `InstallArtifact` step instead of branching on
  the OS, so the convention cannot drift from Zig's again. `library_filename`
  is now `dest_sub_path`, and the new `GoBindings.library_path` field saves
  consumers from joining a directory themselves.
- `#cgo LDFLAGS` still points at `zig-out/lib` (build.zig:616) and is left
  alone: that is where the static archive and the Windows import library
  belong, and it is a link-time path, not the runtime artifact.
- Sweep: three purego example loader tests pick `bin` or `lib` from
  `runtime.GOOS`; `08-telemetry-hub`'s policy lists both `../../zig-out/lib`
  and `../../zig-out/bin` so one platform-independent candidate list covers
  every OS (a miss costs nothing and the generated package stays identical
  everywhere); the Windows CI job's `test -f` assertions and both
  `ZIGO_TEST_*` variables moved to `bin`; packaging docs and the two design
  docs updated.
- Verification is path-computation and compile level only, as required.
