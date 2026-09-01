---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Phase notes contain the reproducible spike record and verdict; any
> NEXT: none

# Build spike: cgo + zig cc for Windows, from POSIX

## Planned Work

- From this macOS host, for 01-scalar and 07-event-queue: build the
  Windows static archive (`zig build go-lib -Dtarget=x86_64-windows-gnu`
  — host reflection from plan 57 makes generation work; verify the
  static archive lands in zig-out/lib for windows targets), then
  `CGO_ENABLED=1 GOOS=windows CC="zig cc -target x86_64-windows-gnu"
  go test -c` in the cgo tree. Iterate on failures: record every flag
  error, link error, and workaround (CGO_LDFLAGS, `-Wl,` passthrough,
  zig cc argument quirks) in the phase notes with exact commands.
- Deliver a spike verdict: works / works-with-changes (list them) /
  blocked (diagnose precisely, link upstream issues).
- If works-with-changes: implement the generator/build/doctor changes
  (with goldens and regeneration), keeping POSIX output identical
  unless a `#cgo windows` constraint line is required.
- Use `planr edit` to amend phases 1–2 to match the verdict before
  starting them.

## Done When

- Phase notes contain the reproducible spike record and verdict; any
  required changes are committed with all POSIX suites green; the two
  Windows test executables cross-build from this host (or the blocker
  is documented and phases 1–2 are amended accordingly).

## Notes

**Verdict: works-with-changes — one change, in `build.zig`.**

Host: macOS 15 / arm64, Zig 0.16.0, Go 1.27.0. Both examples
cross-build to runnable-looking Windows PE test executables.

### What failed, and the only failure found

`zig build go-lib -Dtarget=x86_64-windows-gnu` in `examples/01-scalar`
installed `zig-out/lib/scalar_zigo.lib`, but the generated
`#cgo LDFLAGS` line names `${SRCDIR}/../../zig-out/lib/libscalar_zigo.a`.
`std.Build.Step.InstallArtifact` derives the static-archive filename from
the target: `lib<name>.a` on POSIX, `<name>.lib` on Windows. The link
step therefore ended in:

```
$ cd examples/01-scalar/go
$ CGO_ENABLED=1 GOOS=windows GOARCH=amd64 \
    CC="zig cc -target x86_64-windows-gnu" go test -c -o /tmp/scalar_win.exe ./scalar
# example.com/zigo/scalar/scalar.test
.../pkg/tool/darwin_arm64/link: running zig failed: exit status 1
zig cc -target x86_64-windows-gnu -m64 -mconsole -Wl,--tsaware -Wl,--nxcompat \
  -Wl,--major-os-version=6 ... -o $WORK/b001/scalar.test.exe ... \
  .../zig-out/lib/libscalar_zigo.a ... -Wl,--start-group -lmingwex -lmingw32 \
  -Wl,--end-group -lkernel32
error: .../zig-out/lib/libscalar_zigo.a: file not found
```

Nothing else broke. Notably absent from the failure list, i.e. all of
the sharp edges this plan expected and did not hit:

- cgo's compile stage found `zigo_<pkg>.h` through the emitted
  `-I${SRCDIR}/.../zig-out/include` with no changes; zig cc's bundled
  mingw headers and CRT were sufficient.
- Every flag the Go linker passes through `CC` above — `-mconsole`,
  the `-Wl,--tsaware/--nxcompat/--dynamicbase/--high-entropy-va`
  hardening set, `-Wl,--major-os-version=...`, `-Wl,-T,<script>` for
  the gdb-scripts fix-up, and the `--start-group ... -lmingwex
  -lmingw32 --end-group -lkernel32` closing group — was accepted by
  zig cc verbatim. No `CGO_LDFLAGS`, no `-Wl,` rewriting, no response
  file trouble.
- The Go external linker consumed the Zig-produced COFF archive
  directly; no import library, no `.def` munging beyond the
  `export_file.def` Go generates itself.
- `runtime/cgo` callback trampolines and `cgo.Handle` needed nothing:
  07-event-queue, which is entirely about callbacks, linked on the
  first attempt once the archive name matched.

### The change

`build.zig`: when the link mode is static and the target OS is windows,
install the archive as `lib<pkg>_zigo.a` via
`addInstallArtifact(lib, .{ .dest_sub_path = ... })`. `zig cc` links a
`.a`-suffixed COFF archive on Windows without complaint, so renaming
the install is strictly cheaper than teaching the generator a per-OS
filename: `emit.zig` is untouched, no golden changes, no regeneration,
and the emitted `#cgo` block stays byte-identical across every host and
target — which was the stated preference. `installedLibraryPath` reads
`dest_sub_path` back off the step, so `go-doctor` follows automatically.
Dynamic (DLL) installs are untouched, so the plan-56 `bin/` placement
and the purego loader's `DefaultLibraryName` are unaffected.

### Reproduction after the change

```sh
cd examples/01-scalar
rm -rf zig-out && zig build go -Dtarget=x86_64-windows-gnu
ls zig-out/lib          # libscalar_zigo.a
cd go && CGO_ENABLED=1 GOOS=windows GOARCH=amd64 \
  CC="zig cc -target x86_64-windows-gnu" go test -c -o /tmp/scalar_win.exe ./scalar
file /tmp/scalar_win.exe   # PE32+ executable (console) x86-64, for MS Windows

cd ../../07-event-queue
rm -rf zig-out && zig build go -Dtarget=x86_64-windows-gnu
cd go && mkdir -p /tmp/eqwin && CGO_ENABLED=1 GOOS=windows GOARCH=amd64 \
  CC="zig cc -target x86_64-windows-gnu" go test -c -o /tmp/eqwin ./...
ls /tmp/eqwin           # cgo.test.exe  event_queue.test.exe
```

Both produce PE32+ console executables. This is build-level proof only;
runtime proof is phase 1's job on windows-latest.

### POSIX regression check

`zig fmt --check`, `zig build check`, `zig build test`, and
`zig build check` for both Windows arches all pass. All ten cgo example
trees (`zig build test go-check abi-check`, `zig build go`,
`go test ./...`) and all four purego trees pass, with
`git status --porcelain --untracked-files=all -- examples` empty — no
generated drift.

### Consequences for phases 1 and 2

The verdict is positive, so phases 1 and 2 keep their success-path
shape; both were amended only to name the concrete envelope the spike
proved (the archive rename, and the cross leg being near-free and
therefore in scope).
