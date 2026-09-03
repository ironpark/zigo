---
perf_phase: false
status: planned
---
> DONE-WHEN: An import-declared `linkSystemLibrary`/`linkFramework`/`addLibraryPath` appears in the generated cgo block exactly once and the full verification loop passes.
> NEXT: none

# Transitive link inputs

## Planned Work

- Generalize the static-input collector to gather `.system_lib`, frameworks and `lib_paths` across imports with dedup and stable order; route the result into the existing flag strings; add a build-level test with an imported module declaring a system library and a framework; docs and CHANGELOG.

## Done When

- An import-declared `linkSystemLibrary`/`linkFramework`/`addLibraryPath` appears in the generated cgo block exactly once and the full verification loop passes.
