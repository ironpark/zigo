# GOALS

## Problem and the end result from the user's point of view

Everything merged since 0.20.0 is the plugin contract 2.0 work and it is not
published. Users still get 0.20.0 from the documented fetch line, so the new
plugin API, the `plugin_config` migration and the option lookup fix are
unreachable. The end result is a published 0.21.0 GitHub release whose notes
state the breaking changes and the migration.

## Measurable goals

- `CHANGELOG.md` has a `## [0.21.0]` section that lists the breaking plugin
  contract change, the `go_must_variants` to `plugin_config` migration and the
  option attachment fix.
- `build.zig.zon`, `README.md` and `docs/getting-started.md` all reference
  0.21.0.
- Tag `0.21.0` exists on the release commit and the Release workflow publishes
  the GitHub release from that section.

## Supported scope and non-goals

Scope is the release checklist in `docs/development.md`: changelog section,
version bump, fetch lines, format check, test suite, example generated-tree
check, staticcheck, release commit, tag and push. No behaviour changes and no
new features go into this release.

## Reference source / commit / license

Baseline is `cbe4ea3e`, the tip of main after `181-plugin-option-attachment`.
Previous release plan: `177-materialized-callback-fixes#2` for 0.20.0.

## Completion criteria for the whole plan

Release checks pass, main and the `0.21.0` tag are pushed and the GitHub
release is published with the extracted changelog section.
