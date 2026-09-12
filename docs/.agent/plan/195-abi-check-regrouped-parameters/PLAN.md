---
completed_at: "2026-09-12T05:21:43Z"
depends_on:
- options-positional-mix-and-goldens
description: abi-check가 파라미터 재구성을 여러 주석의 변경으로 오보하던 문제를 고치고 C와 Go 표면을 따로 판정한다
plan_status: done
registered_at: "2026-09-12T05:21:34Z"
---
> NEXT: phase 0(`regrouped-parameter-reports`) 하나뿐이고, 그 작업과 검증이 끝나면 이 계획도 끝납니다. ([Phase 0](phases/00-regrouped-parameter-reports.md))

# Phases

- [x] [Phase 00: 재구성된 파라미터 목록의 정확한 보고](phases/00-regrouped-parameter-reports.md)

# Shared Verification

- `zig build test` -- abi_diff 단위 테스트와 모든 generator case 골든.
- 새 테스트에 일부러 틀린 단언을 넣어 실패하는지 확인 -- 테스트가 실제로 실행되는지 검증.
- 실제 semantic 두 개로 `zigo-gen abi-diff --base ... --current ...`: 재구성은 한 줄,
  정렬을 지킨 flatten 재구성은 무보고.
- `cd examples/07-event-queue && zig build abi-check go-check`.
- 문서 링크·anchor 검사와 `zig fmt --check`.

# Decisions That Constrain Ordering

단일 phase입니다. `194-options-positional-mix-and-goldens`가 만든 재구성이 이 검사의
실제 사례라 그 뒤에 옵니다.

# Next Implementation Target

phase 0(`regrouped-parameter-reports`) 하나뿐이고, 그 작업과 검증이 끝나면 이 계획도 끝납니다.
