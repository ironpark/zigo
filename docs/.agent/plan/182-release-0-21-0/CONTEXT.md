# SCOPE

Release only: changelog, version metadata, install instructions, the checks
`scripts/release.sh` runs, the release commit, the tag and publication.

# CONTEXT

## Current implementation and bottlenecks

`scripts/release.sh <version>` runs steps 1 through 5 and 7 through 8 of the
checklist, but it refuses to run without a `## [Unreleased]` section carrying
entries, and `CHANGELOG.md` currently has none. The ten commits since the
0.20.0 tag are the four plugin plans (178 through 181), which change the public
plugin contract to 2.0 and replace the `go_must_variants` build option.

## Target structure and invariants

The version is a minor bump because the plugin contract and the generator
`--plugin-config` input changed. The changelog section names the migration for
both plugin authors and `addGoBindings` users, and the tag has no `v` prefix so
it matches the section heading the workflow extracts.
