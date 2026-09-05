# SCOPE

- `CHANGELOG.md`, `build.zig.zon`, `README.md`, `docs/getting-started.md`.

# CONTEXT

## Current implementation and bottlenecks

`docs/development.md` describes the five release steps; the tag push runs the release workflow.

## Target structure and invariants

Tag name equals the CHANGELOG section name, without a `v` prefix.
