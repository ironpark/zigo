---
completed_at: "2026-08-31T17:51:24Z"
description: GitHub Actions CI를 Ubuntu 단일 플랫폼으로 줄이고 기존 핵심 검증을 유지한다.
plan_status: done
registered_at: "2026-08-31T17:49:46Z"
---
> NEXT: GitHub Actions를 Ubuntu 단일 runner 구성으로 줄이고 핵심 검증을 실행한다. ([Phase 0](phases/00-collapse-ci-to-ubuntu.md))

# Phases

- [x] [Phase 00: Collapse CI to Ubuntu](phases/00-collapse-ci-to-ubuntu.md)

# Shared Verification

- Ruby YAML parser 또는 동등한 parser로 `.github/workflows/ci.yml` 구문 확인
- `rg`로 Ubuntu 외 runner와 matrix 참조가 없는지 확인
- `zig build test --summary all`
- `examples/08-telemetry-hub`의 `zig build purego-go-verify --summary all`과 Go test

# Decisions That Constrain Ordering

단일 phase에서 runner 축소와 검증을 함께 수행한다.

# Next Implementation Target

GitHub Actions를 Ubuntu 단일 runner 구성으로 줄이고 핵심 검증을 실행한다.
