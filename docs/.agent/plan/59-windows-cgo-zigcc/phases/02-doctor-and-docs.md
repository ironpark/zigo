---
depends_on:
- "59-windows-cgo-zigcc#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Doctor reflects reality; docs contain no stale hedges; grep finds no
> NEXT: none

# Doctor and docs

## Planned Work

Amended after the phase 0 spike returned **works-with-changes**. The
spike also narrowed what doctor actually needs:

- The C-compiler probe already accepts `zig cc`: it reads `go env CC`
  and probes `firstWord(CC) --version`, so `CC="zig cc"` probes `zig`
  and passes. What it gets wrong is only the report — it prints
  `PASS C compiler: zig`, dropping the rest of the command line, which
  is exactly the part a reader needs to see when `CC` is a multi-word
  driver. Fix the reporting to name the configured `CC` in full while
  still probing the first word; keep the existing FAIL paths.
- The cgo cross-target `FAIL` stays a FAIL — the spike proved a cgo
  cross build works, but only when the caller also sets `GOOS`,
  `CGO_ENABLED=1` and a `-target`-carrying `CC`, none of which the
  doctor can observe from a `zig build -Dtarget=...` invocation. Do not
  weaken it to a SKIP on the strength of an envelope doctor cannot
  verify. Make the message actionable instead: say that the archive
  cross-builds and point at the documented cross recipe.
- Docs: replace plan 56's "unvalidated future work" hedge on Windows
  cgo with the proven recipe — native (`CC="zig cc"`, no mingw) and
  cross (`CC="zig cc -target x86_64-windows-gnu"` with `GOOS=windows`)
  — and note the gnu-ABI-only, x86_64/aarch64 scope. Update the
  platform support table wherever it lives.

## Done When

- Doctor reflects reality and its unit tests cover the changed lines;
  docs carry the recipe with no stale "unvalidated"/mingw-required cgo
  Windows text; `planr overview` shows the plan done.
