# GOALS

## Problem and the end result from the user's point of view

tagged union 접근은 항상 projection FFI 왕복을 거친다. tag 확인과 payload 읽기가 별도
호출이므로, payload가 전부 스칼라인 작은 union을 반복해서 들여다보는 Go 코드는 cgo
왕복 비용을 그대로 지불한다. 사용자가 원할 때 union 한 개를 **한 번의 호출로 값 스냅샷**
으로 읽어올 수 있어야 한다.

## Measurable goals

- payload가 void/scalar/enum 뿐인 union을 opt-in으로 값 스냅샷 표현으로 노출한다.
- 값 스냅샷 경로에서 tag + payload 읽기가 native 호출 1회로 끝난다.
- 적격하지 않은 union에 opt-in하면 진단으로 거부한다.
- 값 스냅샷 union의 variant 추가를 ABI diff가 breaking으로 판정한다.
- cgo와 purego 두 백엔드가 동일한 공개 Go API를 제공한다.

## Supported scope and non-goals

- 범위: semantic IR의 repr 확장, validate 적격 조건, lower/emit(C 헤더·shim·Go 2종),
  ABI diff 규칙, 예제와 문서.
- 비범위: 기존 projection 표현 제거나 기본값 변경. slice·opaque handle·중첩 aggregate
  payload의 값 노출. Zig union의 실제 메모리 배치를 C로 복제하는 방식.

## Reference source / commit / license

현재 브랜치의 `src/gen/{validate,lower,emit,abi_diff}.zig`, `src/reflect/walk.zig`,
`examples/10-tagged-union`. 설계 근거는 `docs/.agent/design/03-lowering-rules.md` §7과
`05-implementation-status.md` §1.1.

## Completion criteria for the whole plan

opt-in한 예제가 값 스냅샷으로 tag와 payload를 읽고, cgo·purego 테스트가 통과하며,
적격성 진단과 ABI 규칙에 스냅샷 테스트가 있다.
