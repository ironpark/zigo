---
depends_on:
- out-slice-written
description: 캐스트 적격 struct 슬라이스 반환에서 공개 계층의 원소별 복사를 재해석으로 대체
plan_status: in-progress
registered_at: "2026-09-02T05:01:41Z"
---
> NEXT: 세 반환 지점을 재해석 도우미로 바꾸고 적격 타입의 `SliceFromRaw` 생성을 끊는다. ([Phase 0](phases/00-reinterpret-return.md))

# Phases

- [ ] [Phase 00: 적격 struct 슬라이스 반환의 재해석](phases/00-reinterpret-return.md)

# Shared Verification

- `zig build test --summary all`; 예제 루프(`docs/development.md`) + purego 4개.
- 골든 갱신은 실패 출력의 actual 경로를 `zig build snapshot -- <expected> <actual> --update-snapshots`에 넘긴다.

# Decisions That Constrain Ordering

단일 phase. 계획 65와 독립이지만 `0.1.0` 태그 뒤에 진행한다.

# Next Implementation Target

세 반환 지점을 재해석 도우미로 바꾸고 적격 타입의 `SliceFromRaw` 생성을 끊는다.
