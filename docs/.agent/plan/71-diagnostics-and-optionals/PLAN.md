---
completed_at: "2026-09-02T10:31:39Z"
depends_on:
- third-party-library-fit
description: 스칼라 optional, 공개 Go 이름 충돌 진단, 진단의 소스 위치, 태그 릴리즈 자동화
plan_status: done
registered_at: "2026-09-02T07:40:11Z"
---
> NEXT: 공개 Go 이름 충돌을 생성 시점 진단으로 잡는다. ([Phase 0](phases/00-public-name-collision.md))

# Phases

- [x] [Phase 00: 공개 Go 이름 충돌 진단](phases/00-public-name-collision.md)
- [x] [Phase 01: 진단의 소스 위치](phases/01-diagnostic-source-location.md)
- [x] [Phase 02: 스칼라·enum·extern struct optional](phases/02-scalar-optionals.md)
- [x] [Phase 03: 슬라이스·문자열 optional](phases/03-slice-optionals.md)
- [x] [Phase 04: 태그 릴리즈 자동화와 fetch 고정](phases/04-release-automation.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`.
- 예제 루프 + purego 4개. 골든 갱신은 실패 출력의 actual 경로 사용.

# Decisions That Constrain Ordering

0, 1, 2, 4는 독립. 3은 2 뒤. 권장: 0 → 1 → 4 → 2 → 3(작은 것부터). 2·3은 ABI 추가라 기존 바인딩 불변, breaking 아님.

# Next Implementation Target

공개 Go 이름 충돌을 생성 시점 진단으로 잡는다.
