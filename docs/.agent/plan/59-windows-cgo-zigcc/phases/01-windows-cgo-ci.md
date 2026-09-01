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
