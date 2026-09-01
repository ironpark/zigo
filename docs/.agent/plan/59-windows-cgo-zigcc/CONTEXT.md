# SCOPE

Files potentially changing (spike decides the exact set): `src/gen/
emit.zig` (cgo `#cgo` block emission if flags/paths need Windows
variants), `build.zig` (cgo cross/native wiring, doctor invocation),
`src/gen/doctor.zig` (C-compiler probe recognizing zig cc; cgo cross
target messaging), `.github/workflows/ci.yml`, docs, goldens, and cgo
example trees if emission changes. Public Go API unchanged.

# CONTEXT

## Current implementation and bottlenecks

- Generated cgo package: `#cgo CFLAGS: -I${SRCDIR}/../../../zig-out/
  include`, `#cgo LDFLAGS: ${SRCDIR}/../../../zig-out/lib/
  lib<name>_zigo.a` plus per-example system libs (04 adds `-lz`).
  Forward-slash relative paths; static archive produced by Zig.
- On Windows, Zig installs a DLL to `bin` — but the cgo backend builds a
  STATIC library, which stays in `zig-out/lib` (plan 56's doctor fix
  reads the path from the install step, so this should already be
  correct; verify rather than assume).
- Doctor for cgo: probes CGO_ENABLED, a C compiler, and hard-FAILs
  cross targets (plan 57 relaxed this for purego only).
- `cgo.Handle` and the callback dispatch used by the cgo backend are
  platform-independent Go; the C side is Zig-compiled. Windows-specific
  risk sits in the link step (COFF archive member handling by the Go
  external linker + zig cc as the linker driver) and in any flags cgo
  injects that zig cc rejects.
- windows-latest runners have Go and (via setup action) Zig; no mingw
  assumption allowed.

## Target structure and invariants

- Native Windows: `CGO_ENABLED=1 CC="zig cc" go test` on windows-latest
  links the Zig-built static archive through zig cc's lld. If cgo
  injects flags zig cc rejects, prefer fixing via emitted `#cgo` flags
  or documented `CGO_*FLAGS` env in CI over patching user toolchains.
- Cross (stretch, only if the spike shows it near-free): POSIX host,
  `CC="zig cc -target x86_64-windows-gnu" GOOS=windows CGO_ENABLED=1
  go test -c`, executables shipped to the Windows job as artifacts.
- Doctor: recognizes `zig cc` as a valid C compiler (its probe should
  not demand literal gcc/clang binaries); cgo cross-target messaging
  updated only as far as the spike's supported envelope.
- The emitted `#cgo` block stays identical across hosts unless the
  spike proves a Windows-conditional line is unavoidable (cgo supports
  `#cgo windows LDFLAGS:` constraints — use them rather than forking
  files if needed).
- CI keeps the plans-56/57 shape: compile-level proof locally, runtime
  proof on CI, fix-forward loop on failure.
