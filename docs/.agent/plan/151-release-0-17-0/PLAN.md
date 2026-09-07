---
description: Validate and publish 0.17.0 with generator plugins and review corrections
plan_status: in-progress
registered_at: "2026-09-07T10:49:38Z"
---
> NEXT: Prepare the changelog and run all release checks. ([Phase 0](phases/00-prepare-release.md))

# Phases

- [ ] [Phase 00: Prepare the release](phases/00-prepare-release.md)
- [ ] [Phase 01: Publish and verify](phases/01-publish-and-verify.md)

# Shared Verification

Release script checks formatting, all tests, cgo/purego example freshness and staticcheck. Verify remote tag and release workflow through GitHub API.

# Decisions That Constrain Ordering

Prepare before publishing.

# Next Implementation Target

Prepare the changelog and run all release checks.
