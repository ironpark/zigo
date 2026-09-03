# SCOPE

- New `Options.install: Install = .{}` struct with the four fields above; keep every existing default identical so current consumers see no change in generated files (goldens and example generated files must not change unless the example opts in).

# CONTEXT

## Current implementation and bottlenecks

- `include_dir`/`library_dir` computed from `b.install_path` joined with fixed `include`/`lib` and passed to the generator as `--include-dir`/`--library-dir`.
- `addInstallArtifact` with default `dest_dir`; Windows shared libraries land in `bin`, which `installedLibraryPath` already accounts for.

## Target structure and invariants

- One place computes the library and header install directories and names; every consumer (generator flags, static archive installs, purego loader, `Bindings` fields) reads from it.
