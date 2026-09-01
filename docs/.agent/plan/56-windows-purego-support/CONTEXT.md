# SCOPE

Files expected to change: `src/gen/emit.zig` (loader emission split into
tagged files, `DefaultLibraryName` windows entry, any windows-specific
symbol resolution), `src/build_options.zig`, `src/gen/doctor.zig`,
goldens under `tests/`, regenerated `examples/*/go-purego` trees,
`.github/workflows/ci.yml`, and docs. The generated public API of purego
packages must not change shape; a new build-tagged file per package is
expected (subject to the plan-49 no-empty-file rule).

# CONTEXT

## Current implementation and bottlenecks

- `build_options.zig:9` — `puregoTargetSupported` returns true only for
  macos/linux on x86_64/aarch64; doctor renders "purego bindings require
  macOS or Linux on amd64/arm64" on failure and gates generation flows.
- `emit.zig:1022` — `DefaultLibraryName` map literal contains only darwin
  and linux keys; on other GOOS the lookup yields "".
- Generated loader (`examples/*/go-purego/internal/raw/raw_gen.go`) calls
  `purego.Dlopen(path, RTLD_NOW|RTLD_LOCAL)` and resolves symbols with
  `purego.Dlsym`; callback dispatch uses purego trampolines that purego
  supports on Windows as well.
- Library loading policy (plan 33) defines explicit/automatic loaders and a
  documented security note; the Windows path must plug into the same policy
  surface.
- CI (`.github/workflows/ci.yml`) has two ubuntu-latest jobs (plan 45).
- Purego trees run with `CGO_ENABLED=0`; the race detector is unavailable
  there (documented in plan 55) — same holds on Windows.

## Target structure and invariants

- Loader file split: the OS-specific load/lookup primitives move to
  `..._load_posix_gen.go` (`//go:build !windows`) and
  `..._load_windows_gen.go` (`//go:build windows`), each defining the same
  small internal functions (open library, resolve symbol, error text);
  everything else stays shared and identical. Exported API and error
  wrapping remain byte-identical across OSes.
- Windows loading uses `syscall.LoadLibrary` + `syscall.GetProcAddress`
  (stdlib; avoid adding a golang.org/x/sys dependency unless purego's own
  Windows helpers make it unnecessary — decide from purego v0.10.2's public
  API and record the choice).
- Naming: `<name>_zigo.dll` (Windows convention: no lib prefix); doctor and
  docs state all three names.
- `zig build go-lib` cross-target flow produces the DLL under the same
  output layout so `ZIGO_TEST_LIBRARY` and default resolution work
  unchanged.
- Windows CI job: setup Zig + Go, `zig build go-lib` natively, run purego
  suites; plus one cross-compile proof — a DLL built in the Ubuntu job (or
  in the Windows job via an explicit `-Dtarget` from a WSL-free zig
  invocation) uploaded/consumed, or a simpler equivalent the implementer
  justifies. Keep total CI time reasonable.
- gofmt/vet clean on generated tagged files; goldens cover both tag
  variants.
