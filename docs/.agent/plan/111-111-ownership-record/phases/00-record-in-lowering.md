---
completed_at: "2026-09-05T07:54:17Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test` 녹색, golden 44개 바이트 동일.
> NEXT: none

# Record in lowering

## Planned Work

- `abi.zig`에 `Ownership`, `ParamOwnership`, `ReleaseTarget`를 추가하고 `AbiFn.ownership`,
  `AbiFn.param_ownership` 필드를 기본값과 함께 넣는다.
- `lower.zig`에 `releaseTarget`(이름으로 release 함수를 찾아 노출 파라미터 하나와 `void` 반환을
  요구; validate의 `releaseCandidateParameter`와 같은 규칙)과 `ownershipOf`, `paramOwnershipOf`를
  추가하고 lowering 루프가 두 필드를 채운다. `release_symbol` 해석 루프는 `ownershipOf`의 결과에서
  채운다.
- 기존 `AbiFn` 필드와 emit은 건드리지 않는다.
- `lower.zig` 테스트: 설계 문서 1.2의 13행을 덮는 golden case(`complex`, `root_constructor`,
  `dependent_handle`, `borrowed_return`, `optional_slice`, `narrow_int`, `materialized`,
  `callback_error`, `io_stream`, `value_struct`, `injection`)의 대표 함수를 골라 기대 레코드를 단언한다.

## Done When

- `zig build test` 녹색, golden 44개 바이트 동일.
- 위 테스트가 13행 각각에 대해 최소 하나의 함수를 단언한다.
