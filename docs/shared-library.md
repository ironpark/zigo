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

Callbacks remain cgo-only until the callback function-pointer ABI phase. A
purego configuration containing callbacks fails generation with a diagnostic.
