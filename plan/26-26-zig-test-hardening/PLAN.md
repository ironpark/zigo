---
description: Harden Zig tests by running every example in CI, validating semantic references, wiring negative fixtures, and adding parser, CLI, build-option, and lowering coverage.
plan_status: in-progress
registered_at: "2026-08-30T09:37:22Z"
---
> NEXT: 8개 example의 Zig 테스트를 표준 build step과 CI에 연결한다. ([Phase 0](phases/00-example-test-discovery-and-ci.md))

# Phases

- [ ] [Phase 00: Example test discovery and CI](phases/00-example-test-discovery-and-ci.md)
- [ ] [Phase 01: Semantic referential integrity](phases/01-semantic-referential-integrity.md)
- [ ] [Phase 02: Negative process integration](phases/02-negative-process-integration.md)
- [ ] [Phase 03: Parser and lowering unit coverage](phases/03-parser-and-lowering-unit-coverage.md)
- [ ] [Phase 04: Build options and full matrix](phases/04-build-options-and-full-matrix.md)

# Shared Verification

- root `zig build test --summary all` 및 `zig build check --summary all`
- 8개 example의 `zig build test`와 `zig build go-check abi-check`
- 8개 Go module의 `go test -count=1 ./...`
- expected-failure fixture의 exit/diagnostic assertion
- `zig fmt --check .` 및 `git diff --check`

# Decisions That Constrain Ordering

먼저 기존 example 테스트를 실제 CI 경로에 올린다. 그 기준선 위에서 panic 원인을 제거한 뒤
process integration, parser/lowering unit, build helper 순으로 국소 테스트를 추가하고 전체
matrix로 마무리한다.

# Next Implementation Target

8개 example의 Zig 테스트를 표준 build step과 CI에 연결한다.
