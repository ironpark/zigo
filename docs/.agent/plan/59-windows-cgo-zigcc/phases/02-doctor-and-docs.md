---
completed_at: "2026-09-01T19:14:12Z"
depends_on:
- "59-windows-cgo-zigcc#0"
perf_phase: false
status: done
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

## Notes

### Doctor

`go env CC` is now read as a whole command line rather than reduced to
its first word. The probe still runs the first word (`zig` for
`CC="zig cc"`), but the report prints the full value, and the failure
line names both — `zig cc is configured by \`go env CC\` but zig is not
executable`. Covered by a new unit test for both the pass and fail
paths; the existing test also pins `PASS C compiler: cc` so the POSIX
report did not change shape.

The cgo cross-target check stays a `FAIL`, deliberately. The archive
does cross-build and `zig cc` does link it — phase 1's
`cgo-windows-cross` job proves the result runs — but that depends on
`GOOS`, `CGO_ENABLED` and a `-target`-carrying `CC` on the Go side,
none of which a `zig build -Dtarget=...` invocation can observe.
Downgrading it to `SKIP` would assert an envelope doctor cannot check.
The message now says what it can: that the check cannot be *validated*
from a cross build, and where the recipe is. `build.zig`'s CLI contract
expectation moved with it.

### Docs

- `docs/getting-started.md`: new "Windows에서 cgo 백엔드 쓰기" section
  with copy-pasteable native (PowerShell) and cross (bash) recipes,
  plus the three caveats — gnu ABI/amd64 only, the `lib<name>_zigo.a`
  archive name, and the expected `FAIL target` on a cross build.
  준비 사항 now lists Windows as a supported host.
- `docs/limitations.md`: the cgo envelope is macOS/Linux/Windows; the
  "mingw 링크는 후속 작업" line is gone. The cross-compilation bullet
  now covers both backends instead of calling cgo cross "검증하지 않았다".
- `docs/generated-code.md`: documents why the Windows archive is named
  `lib<name>_zigo.a` rather than Zig's `<name>_zigo.lib`.
- `README.md` and `docs/purego.md`: support tables and the purego
  known-limitations list no longer say Windows lacks a cgo backend.
  The purego race-detector note dropped its "Windows has no cgo
  backend, so no race coverage there" clause.
- `docs/development.md`: names both Windows CI jobs.

`grep -rn "unvalidated\|mingw" docs/ README.md` returns only the new
text explaining that mingw-w64 is *not* required.
