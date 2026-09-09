---
description: 사용자 문서를 독자 여정별 구조로 전면 재작성하고 마이그레이션과 플러그인 문서를 분리한다
plan_status: in-progress
registered_at: "2026-09-08T17:03:09Z"
---
> NEXT: 새 정보 구조와 온보딩 문서를 구현하고 마이그레이션 문서를 제거한다. ([Phase 0](phases/00-foundation-and-onboarding.md))

# Phases

- [x] [Phase 00: Foundation and onboarding](phases/00-foundation-and-onboarding.md)
- [x] [Phase 01: Binding authoring guides](phases/01-binding-authoring-guides.md)
- [x] [Phase 02: Build, distribution, and reference](phases/02-build-distribution-and-reference.md)
- [ ] [Phase 03: Plugins and internal contracts](phases/03-plugins-and-internal-contracts.md)
- [ ] [Phase 04: Examples and repository-wide verification](phases/04-examples-and-verification.md)

# Shared Verification

- Markdown 상대 링크와 제목 anchor 검사
- `rg`로 마이그레이션 및 제거된 경로 참조 확인
- `zig build test`
- `zig build examples`
- 최소 예제의 문서화된 생성 및 Go 테스트 명령
- `git diff --check`

# Decisions That Constrain Ordering

탐색과 기본 경로를 먼저 고정한 뒤 작성 가이드, 운영·참조, 플러그인·내부 계약을 순서대로 작성한다. 마지막에 예제 문서와 저장소 전체 링크를 맞춰 중간 구조 변경으로 인한 반복 작업을 줄인다.

# Next Implementation Target

새 정보 구조와 온보딩 문서를 구현하고 마이그레이션 문서를 제거한다.
