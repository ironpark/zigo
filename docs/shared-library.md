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
