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
