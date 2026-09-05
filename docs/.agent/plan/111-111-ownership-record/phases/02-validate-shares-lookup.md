---
depends_on:
- "111-111-ownership-record#1"
perf_phase: false
status: planned
---
> DONE-WHEN: `zig build test` 녹색, golden 44개 바이트 동일, `snapshot_tests.zig` 변경 없음.
> NEXT: none

# Validate shares the release lookup

## Planned Work

- `validate/ownership.zig`의 `releaseTargetIssue`(ZIGO016), `validate/materialized.zig`의
  `materializedReleaseTargetIssue`(ZIGO048), `ownedReturnIsWrappable`(ZIGO015)이
  `lower.releaseTarget`과 `lower.ownedOpaqueReturn`을 읽도록 바꾸고 `releaseCandidateParameter`를
  지운다.
- payload 벗기기를 `TypeNode.errorPayload` 위의 두 함수로 줄인다. 소유권 질문은
  `releasableSliceReturnElement`(optional까지 벗김), 호출 규약 질문은 `lower.sliceReturnElement`.
  `borrowedOpaqueReturn`과 `ownedOpaqueReturn`은 `errorPayload`를 쓴다.
- 기존 진단 스냅샷 테스트가 그대로 통과하는지 확인하고, 규칙이 한 곳으로 모였다는 테스트를
  하나 추가한다(주입 allocator를 받는 release 함수를 ZIGO016과 ZIGO048이 같은 helper로 받아들인다).

## Done When

- `zig build test` 녹색, golden 44개 바이트 동일, `snapshot_tests.zig` 변경 없음.
- `releaseCandidateParameter`가 사라지고 release 후보 판정 함수가 `lower.releaseTarget` 하나다.
