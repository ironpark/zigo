---
depends_on:
- "59-windows-cgo-zigcc#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: CI green on all runners including the new job; the job's added time
> NEXT: none

# Windows cgo CI job

## Planned Work

Amended after the phase 0 spike returned **works-with-changes**: the
only change was `build.zig` installing the Windows static archive as
`lib<pkg>_zigo.a`, and the POSIX→Windows cross leg turned out to be
free (`go test -c` produced PE32+ executables for both examples on the
first try after the rename). Both legs below are therefore in scope.

- Add a `cgo-windows` job on windows-latest: setup Zig 0.16.0 + Go,
  no mingw, `core.autocrlf false` like the purego job. For 01-scalar
  and 07-event-queue run `zig build go` natively, assert
  `zig-out/lib/lib<pkg>_zigo.a` exists (this is the archive-name fix
  the spike produced, and the assertion is what keeps it from silently
  regressing), then `CGO_ENABLED=1 CC="zig cc" go vet ./... &&
  go test ./...`. No extra `CGO_CFLAGS`/`CGO_LDFLAGS` — the spike
  showed none are needed.
- Exclude 04-callback with a comment: it links system zlib, which
  windows-latest does not provide. Same reason the purego job excludes
  it.
- Add the cross leg, since the spike proved it near-free: the Ubuntu
  job cross-builds the two examples' Windows cgo test executables with
  `CGO_ENABLED=1 GOOS=windows CC="zig cc -target x86_64-windows-gnu"
  go test -c`, uploads them as an artifact, and a
  `cgo-windows-cross` job runs them on windows-latest. That is the
  half a POSIX host cannot check, mirroring `purego-windows-cross`.
- Ride the CI loop: push, fix-forward on failure as further commits in
  this phase, or a new phase if the class of failure warrants it. Do
  not claim Windows runtime success before CI is green.

## Done When

- CI green on all runners including the new job(s); the added wall time
  recorded in phase notes.

## Notes

CI green on all six jobs at commit `f13c1f2` (run 33545759305):
`test` 153s, `purego` 113s, `purego-windows` 247s,
`purego-windows-cross` 39s, **`cgo-windows` 244s**,
**`cgo-windows-cross` 5s**. The two new jobs run in parallel with the
existing ones, so the added wall time is ~0; `cgo-windows` becomes the
job the run's duration is bounded by, alongside `purego-windows`.

Both legs shipped: native (windows-latest, `CC="zig cc"`, no mingw) and
cross (executables built on the Ubuntu job, run on Windows). The cross
leg is 5s because the static archive is already linked in — the
downloaded executables need no zig-out, no DLL, and no checkout.

### The one CI-only failure, and what it actually was

The first run's `cgo-windows` failed at the suite step with
`fatal error: 'zigo_scalar.h' file not found` while
`cgo-windows-cross` — the same tests, cross-built from macOS/Ubuntu —
passed. Job logs are not readable from this host, so the resolved flags
were surfaced as `::warning::` annotations instead, which are. They
named the cause outright:

```
pkg dir:     D:\a\zigo\zigo\examples\01-scalar\go\scalar
cgo cflags:  [-ID:/a/zigo/zigo/examples/01-scalar/go/scalar/....zig-outinclude]
cgo ldflags: [D:/a/zigo/zigo/examples/01-scalar/go/scalar/....zig-outlib/libscalar_zigo.a]
```

`build.zig`'s `cgoRelativePath` used `std.fs.path.relative`, which
answers in the **host** separator. Generating on Windows therefore
emitted `-I${SRCDIR}\..\..\zig-out\include` into the `#cgo` block, and
cgo's `${SRCDIR}` expansion swallowed every backslash — `\..\..` became
`....`, `\zig-out\include` became `zig-outinclude`. The header was
present the whole time; the flag pointed at a path that never existed.
Fixed in `b8707e8` by normalizing the relative path to forward slashes,
which is also what keeps the committed bytes host-independent.

This was a latent bug, not one this plan introduced: nothing had ever
generated a cgo tree on Windows before. Two things hid it, and both are
now closed:

- `go-check` could not see it. The job regenerates (`zig build go`)
  before checking, so `go-check` compared the Windows output against
  the file `zig build go` had just overwritten. The job now runs the
  Ubuntu job's `git status --porcelain -- examples` assertion, which
  compares against the *committed* files instead.
- The spike could not see it either: generation ran on macOS, and only
  the *target* was Windows. Host-dependent generation needs a Windows
  host, which only CI has. Worth remembering for future spikes — a
  POSIX-host cross build proves the target, never the host.

One self-inflicted failure in between: `b8707e8` carried the phase 2
`build.zig` CLI-contract string without its `doctor.zig` counterpart,
breaking the Ubuntu `test` job. Resolved by landing `doctor.zig` in
`f13c1f2`.
