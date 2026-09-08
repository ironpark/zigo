---
completed_at: "2026-09-08T07:08:06Z"
perf_phase: false
status: done
---
> DONE-WHEN: Release checks pass, main and the `0.21.0` tag are pushed and the GitHub
> NEXT: none

# Release 0.21.0

## Planned Work

- Write the `## [Unreleased]` section covering the plugin contract 2.0
  breaking changes, the `plugin_config` migration and the option lookup fix.
- Run `scripts/release.sh 0.21.0` for the checks, the version bump commit and
  the tag, then push main and the tag once confirmed.
- Verify the Release workflow published the GitHub release with those notes.

## Done When

- Release checks pass, main and the `0.21.0` tag are pushed and the GitHub
  release shows the extracted 0.21.0 section.
