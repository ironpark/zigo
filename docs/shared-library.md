# Shared-library artifact contract

`Options.link_mode = .dynamic` builds a native shared library and the standard
`go-lib` step installs it in `zig-out/lib`. The returned `GoBindings` exposes
the compile step as `lib`, the install step as `install_library`, and the
target-specific basename as `library_filename`.

The native filename follows the target ABI: `lib<name>_zigo.dylib` on macOS and
`lib<name>_zigo.so` on Linux. The library does not embed a Zig-cache path. Its
only runtime dependencies are dependencies of the bound Zig module and the
platform C runtime used by the generated panic boundary. Applications are
responsible for passing an explicit path or arranging their platform loader
search path.

The shared library is target-specific. A native shared build is suitable for
runtime loading; it is not a cross-platform binary or a cross-target generation
mechanism.

## purego backend

Set both `.backend = .purego` and `.link_mode = .dynamic`. The initial backend
supports native macOS and Linux on amd64 and arm64. Generated Go must call
`LoadLibrary(path)` before any binding call; `LibraryLoaded()` reports whether
all symbols were resolved and atomically published. Successful libraries stay
loaded for the process lifetime.

Generated Go selects the platform basename at run time, so the committed loader
is byte-identical on macOS and Linux: `DefaultLibraryName` is
`map[string]string{"darwin": ..., "linux": ...}[runtime.GOOS]`. `LoadLibrary`
resolves its path from the explicit argument, then `ZIGO_LIBRARY_PATH`, then
`DefaultLibraryName` through the platform loader search path.

`Options.library_loading` configures the candidate order: the explicit argument,
then each configured environment variable, then each configured search path,
then the platform default name. It can also load on the first binding call and
keep the loader out of the public package. The default policy is an explicit
`LoadLibrary`, the package-specific and shared environment variables, and the
platform default name. See [the purego page](purego.md) for the full option.

If zigo creates `go.mod`, it pins `github.com/ebitengine/purego v0.10.2`. For an
existing module, add it explicitly:

```sh
go get github.com/ebitengine/purego@v0.10.2
```

Callback-bearing purego libraries use a versioned native entry point ending in
`_purego_v1`. Its C signature contains the callback function pointer explicitly,
followed by the existing integer userdata parameter. Callback types and return
types are lowered from semantic IR and use the C calling convention. The shared
library therefore has no unresolved dependency on a Go `//export` trampoline.

The cgo backend keeps its original symbols and fixed generated trampolines. This
dual-symbol strategy avoids changing an existing cgo ABI in place. Binding
reports identify the backend and callback convention; `abi-diff` accepts
`--base-backend` and `--current-backend` so a backend/convention switch is
reported as breaking rather than mistaken for an unchanged semantic signature.

For purego callbacks, generated code creates one permanent native dispatcher per
unique callback signature. Individual Go callback values live in a synchronized
integer-token registry; native code retains only the dispatcher pointer and the
token, never Go memory. Borrowed tokens are removed after the call. Retained
tokens move into the returned owner and are removed on constructor rollback,
explicit `Close`, or automatic cleanup when enabled. Deletion rejects new
invocations and waits for calls already in flight. Dispatcher recovery converts
Go panics to the existing `-3` callback-panic status for signed 32-bit callback
results; a released token deterministically returns `-4`.

## Validation

`addStandardSteps` registers `go-lib` (build and install the artifact) and
`go-verify`, which aggregates staleness, the installed library, `go-doctor` and,
when `abi_base` is set, `abi-check`. For the purego backend `go-doctor` checks
host platform support, the `go.mod` purego requirement, and loads the installed
artifact with the platform loader; failures name the command that fixes them.

Two repository tools inspect a built artifact directly:

```sh
tests/inspect_shared_library.sh <library> <symbol>...
zig build shared-library-smoke -- <library> <symbol>...
```

The script asserts the platform filename, that no build-cache path is baked into
the runtime dependencies, that the requested symbols are exported, and that no
generated `zg_` symbol is left undefined — an undefined one would mean a cgo
trampoline dependency that a `CGO_ENABLED=0` process cannot satisfy. The smoke
loader performs the same symbol check through the real platform loader.

Both backends can install into one prefix. The cgo raw file links
`lib<name>_zigo.a` by explicit path for a static link mode, and the purego C
header installs as `zigo_<name>_purego.h`, so neither artifact shadows the
other and the order of the two builds does not matter.

Because a shared library is target specific, CI needs one job per supported
OS/architecture pair: macOS and Linux on amd64 and arm64. purego removes the C
compiler from the Go application build; it does not remove the per-target Zig
build. User-facing packaging, loading, and security guidance lives in
[the purego page](purego.md).
