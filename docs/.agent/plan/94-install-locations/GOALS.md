# GOALS

## Problem and the end result from the user's point of view

The native binding library always installs to `<install_path>/lib` (Windows shared libraries to `bin`) and the header to `<install_path>/include`; the generated `#cgo` flags, static link input archives, and purego loader search paths are derived from those fixed directories (`build.zig` around lines 840-841 and 955-1000). A consumer who wants the artifacts somewhere else, for example inside the Go module tree so `go build` works from a checkout, or a `dist/` layout shared with other languages, has no option. The end result: `zigo.addBindings` accepts an `install` option that chooses the library directory, the header directory, and optionally the file names, and every generated path follows.

```zig
.install = .{
    .library_dir = .{ .custom = "dist/lib" },   // std.Build.InstallDir, default .lib
    .header_dir = .{ .custom = "dist/include" }, // default .header
    .library_name = "ghostty_vt",                // default: binding name; stem without lib/ext
    .header_name = "ghostty_vt.h",               // default: zigo_<name>.h
},
```

## Measurable goals

- `install.library_dir` and `install.header_dir` are `std.Build.InstallDir` values (`.lib`, `.bin`, `.header`, `.prefix`, `.custom`), so `zig build -p` still relocates everything and `.custom` may point anywhere under the prefix.
- `install.library_name` and `install.header_name` override file names; static link input archives (`lib<name>.a`) install beside the binding library in the same directory, and the collision check with the binding name stays.
- Generated `#cgo CFLAGS -I` and `LDFLAGS -L` plus the static archive directive resolve to the configured directories, still `${SRCDIR}`-relative with forward slashes; `Bindings.library_path`, `library_filename`, `install_library` report the real locations.
- purego: `library_loading` default search paths and the generated loader honour the configured directory and name; `docs/purego.md` updated.
- The header install name rule for purego (`_purego` suffix when both backends share one prefix) still applies when `header_name` is not set; when set explicitly for both backends with the same name, `addBindings` panics with a clear message.
- `go-coverage`, `go-check`, `abi-check`, and `install` default step keep working; example 05 or 06 exercises a custom layout on cgo, example 08 on purego, Go tests pass from the configured paths.
- `docs/configuration.md` gains the option row and a "설치 위치" section; CHANGELOG `## [Unreleased]` `### Added`.

## Supported scope and non-goals

In scope: `build.zig` (`Options`, `addBindings`, path derivation, `PublishCgoLinkFlags`, `installedLibraryPath`), purego loader emission where it embeds default paths, docs, two example changes.
Non-goals: installing outside the Zig install prefix (use `-p`), copying artifacts into the Go source tree as committed files, changing the generated Go package layout.

## Reference source / commit / license

Current main; plans 75 and 79 (static link inputs, host reflection clone) for how archives are installed; the header-beside-archive dependency (`install_lib.step.dependOn(&install_header.step)`).

## Completion criteria for the whole plan

Phase done; full verification loop green including purego targets; docs and CHANGELOG updated; tree clean.
