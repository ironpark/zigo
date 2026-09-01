---
completed_at: "2026-09-01T16:34:09Z"
depends_on:
- "56-windows-purego-support#5"
perf_phase: false
status: done
---
> DONE-WHEN: Every symbol the generated loader resolves appears in the export table of a
> NEXT: none

# Export the generated C entry points from the DLL

## Planned Work

- `GetProcAddress` cannot find `zg_last_error_message` in a DLL that loads
  fine and whose POSIX counterpart resolves it. ELF and Mach-O export every
  non-static symbol from a shared library; COFF exports nothing without
  `__declspec(dllexport)` or a `.def` file. The generated `panic.c` defines
  its entry points as plain C, so they are absent from the export table.
- Audit the whole resolve list against a real cross-built DLL's export table
  rather than fixing the one symbol CI happened to reach first.
- Emit the export annotation for exactly the symbols the generated Go loader
  resolves, guarded by `_WIN32` so the committed C stays identical on every
  host.

## Done When

- Every symbol the generated loader resolves appears in the export table of a
  locally cross-built `x86_64-windows-gnu` DLL, verified by listing it.
- POSIX stays green: `zig build test`, `check`, the Windows cross `check`s,
  the fourteen Go trees, and no generated drift beyond the intended C change.

## Notes

- Cause, confirmed by reading a real export table rather than reasoning: the
  cross-built `x86_64-windows-gnu` DLL exported 16 names, all of them the
  Zig `export fn` `*_impl` halves, plus `_DllMainCRTStartup`. Every symbol the
  generated loader resolves lives in the generated `panic.c` -- the setjmp
  wrappers and `zg_last_error_message` -- and those are plain C, which COFF
  does not export. The overlap between "exported" and "resolved" was empty, so
  all 16 lookups were broken; CI simply reported the first.
- The audit paid for itself immediately. Annotating only
  `writeCFunctionDeclaration` left 10-tagged-union missing 14 more symbols:
  projection and snapshot wrappers go through `writeCUnionDeclaration`, a
  separate path that also emits into `panic.c`. Fixing the instance would have
  shipped a second round trip through CI.
- Fix: an emitted `ZIGO_EXPORT` macro, `__declspec(dllexport)` under `_WIN32`
  and empty elsewhere, defined identically in the header and in `panic.c`
  under an `#ifndef` guard so including one from the other is harmless. It is
  applied to exactly the public wrappers and `zg_last_error_message`; the
  `_impl` halves and `zg_panic_bridge` stay unexported, since the loader never
  resolves them and the export surface should be the documented one.
- Post-fix audit, by listing the export table of a locally cross-built DLL:
  07-event-queue 16/16 resolved symbols exported, 10-tagged-union 40/40.
  08-telemetry-hub is refused by ZIGO014 (float callback) and 04-callback
  cannot link for Windows at all -- `lld-link: undefined symbol: compressBound`,
  the zlib dependency -- so both are already out of the Windows job. That
  covers every example the job runs.
- Procedure, for repeating this: `zigo-gen generate --target-os windows`
  writes `shim.zig`, `panic.c`, and the header; a five-line `build.zig` that
  feeds the shim a `zigo_target` module pointing at the example's
  `src/root.zig` cross-builds the DLL with `-Dtarget=x86_64-windows-gnu`. The
  reflector only blocks the full pipeline, not this. No LLVM binutils ship
  with Zig 0.16, so the export directory was parsed straight out of the PE
  headers with a short Python script.
- Goldens were updated through `zig build snapshot -- <expected> <actual>
  --update-snapshots` using the case runner's own output, not the CLI: the
  committed goldens are raw generator output and the CLI additionally runs
  gofmt, which would have rewritten every Go golden as spurious drift.
- Gap left open: nothing in CI diffs the export table. The Windows Go suites
  cover it end to end at runtime, which is the check that matters, but a
  regression in a symbol no example resolves would go unnoticed.
