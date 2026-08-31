---
completed_at: "2026-08-31T17:41:23Z"
description: README와 사용자 문서를 작업 흐름 중심으로 재구성하고 내용·링크·명령을 검증한다.
plan_status: done
registered_at: "2026-08-31T17:20:03Z"
---
> NEXT: README와 시작 문서를 기본 cgo 사용자 여정 중심으로 재구성한다. ([Phase 0](phases/00-onboarding-navigation.md))

# Phases

- [x] [Phase 00: Onboarding and navigation](phases/00-onboarding-navigation.md)
- [x] [Phase 01: Reference split and consistency audit](phases/01-reference-split.md)

# Shared Verification

- Markdown 링크 대상을 검사하는 로컬 스크립트 또는 동등한 명령
- `examples/01-scalar`에서 `zig build go-check`와 Go 테스트
- 루트 `zig build test --summary all`
- `rg`로 공개 옵션, 빌드 스텝, 지원 버전과 purego loader 표현을 구현과 교차 확인

# Decisions That Constrain Ordering

먼저 첫 사용자 경로를 안정시킨 뒤 그 경로가 가리키는 상세 참조를 분리한다. 참조 분리는
온보딩 문서의 용어와 링크 구조에 의존한다.

# Next Implementation Target

README와 시작 문서를 기본 cgo 사용자 여정 중심으로 재구성한다.
