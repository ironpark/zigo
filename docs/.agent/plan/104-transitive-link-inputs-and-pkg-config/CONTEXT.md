# SCOPE

- Only the cgo backend's link flags change. Generated Go outside the `#cgo` lines and all goldens stay the same.

# CONTEXT

## Current implementation and bottlenecks

- `staticLibraryInputs` recurses over `import_table`; the three flag builders and `lib_paths` do not.
- `pkgConfigLibraries` copies `library.name` verbatim for `use_pkg_config == .force`.

## Target structure and invariants

- A single `LinkInputCollector` walking the graph once feeds archives, `-l`, `-L`, frameworks and pkg-config names.
- pkg-config resolution happens at build time, never in the generator binary.
