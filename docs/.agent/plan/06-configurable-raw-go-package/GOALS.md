# GOALS

## Problem and the end result from the user's point of view

Generated low-level Go bindings are currently fixed under `internal/raw`. Users can keep that default, choose another relative package directory, or generate the low-level layer beside the public package without creating duplicate Go declarations.

## Measurable goals

- Add a build option covering default, custom-path, and colocated raw-package modes.
- Generate valid package declarations, imports, file names, and collision-free symbols for every mode.
- Exercise custom-path and colocated generation in repository examples and automated tests.

## Supported scope and non-goals

This work changes generated Go source placement and the build/generator interfaces that carry it. It does not change the exported C ABI, public Go wrapper names, or the default layout. Automatic removal of stale generated files after changing modes is out of scope and will be documented as a migration step.

## Reference source / commit / license

The implementation is based on the current repository at `bac2d5f`; no external source is copied.

## Completion criteria for the whole plan

Root Zig tests, every example's generation and consistency checks, ABI checks, and all Go tests pass for the three supported layouts, with documentation explaining configuration and migration.
