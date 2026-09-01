---
completed_at: "2026-09-01T14:58:29Z"
perf_phase: false
status: done
---
> DONE-WHEN: Regenerated purego trees contain the two tagged loader files with
> NEXT: none

# Windows loader emission and platform gate

## Planned Work

- Split the emitted purego loader primitives into build-tagged posix and
  windows files with identical internal contracts; implement the Windows
  path (LoadLibrary/GetProcAddress or purego equivalents — investigate
  purego v0.10.2 first and record the decision), including symbol-missing
  and load-failure error messages of the same shape as POSIX.
- Add the `windows` entry to `DefaultLibraryName`; extend
  `puregoTargetSupported` to windows on x86_64/aarch64; update doctor
  probe text and its unit tests.
- Update purego goldens; regenerate the four purego example trees; run the
  POSIX suites to prove no regression.

## Done When

- Regenerated purego trees contain the two tagged loader files with
  identical exported behavior; `GOOS=windows CGO_ENABLED=0 go vet ./...`
  and `go build ./...` pass for every purego example package on a
  Linux/macOS host (cross-vet/build needs no Windows machine).
- `zig build test` passes; POSIX purego suites stay green.

## Notes

- Loading API decision: purego v0.10.2 exposes **no** public Windows loading
  API. `Dlopen`/`Dlsym`/`Dlclose` are built only for
  `(darwin || freebsd || linux || netbsd) && !android`, and the Windows
  equivalent (`loadSymbol` in `syscall_windows.go`) is unexported. The
  generated Windows half therefore uses the standard library
  `syscall.LoadLibrary` / `GetProcAddress` / `FreeLibrary`, which adds no
  module dependency. `purego.NewCallback` and `RegisterFunc` are supported on
  Windows (Tier 1: amd64, arm64) and stay in the shared file.
- Emitted layout: `<raw>_load_posix_gen.go` (`//go:build !windows`) and
  `<raw>_load_windows_gen.go` (`//go:build windows`), each defining exactly
  `openLibrary`, `closeLibrary`, and `resolveSymbol`. `loadCandidate`, the
  candidate ordering, and every `LibraryError` shape stay in the shared file,
  so the exported surface is byte-identical on all three systems. For the cgo
  backend both emitters produce a bare prelude, which the plan-49 no-empty-file
  rule deletes.
- Blocker found for phases 1 and 2: `zig build go-lib -Dtarget=x86_64-windows`
  cannot work on a POSIX host, and not because of anything in this phase.
  Generation runs `zigo-reflect`, an executable that `addGoBindings` builds for
  `options.target` and then *executes*, so a non-native target dies before the
  library is linked. This is pre-existing and backend-independent; the
  `isRunnableOnHost` panic in `build.zig` was already guarding it. Windows DLLs
  are therefore built natively on Windows, and the cross-built-DLL artifact
  proof is dropped from phase 1.
