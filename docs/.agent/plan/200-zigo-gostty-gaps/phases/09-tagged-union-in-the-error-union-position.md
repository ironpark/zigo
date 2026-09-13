---
completed_at: "2026-09-13T08:16:33Z"
perf_phase: false
status: done
---
> DONE-WHEN: `fn sgrAttribute(...) error{Invalid}!Attribute`가 래퍼 없이 바인딩되고, Go가
> NEXT: none

# Tagged union in the error union position

## Planned Work

- validation이 error union의 payload에 있는 값 union을 바로 자리로 인정하게 한다.
  중첩(`?!Attribute`, slice 원소)은 지금처럼 계속 거절한다.
- lowering의 `value_union_return` 판정이 `errorPayload()`를 보게 한다.
- shim의 값 union 반환 경로가 함수가 선언한 error set을 catch하고, 생략된 variant의
  `-3`과 겹치지 않는 상태 코드를 쓴다.
- generator case로 `!Attribute` 모양을 shim과 Go 양쪽에서 고정한다.

## Done When

- `fn sgrAttribute(...) error{Invalid}!Attribute`가 래퍼 없이 바인딩되고, Go가
  `(Attribute, error)`를 받는다.
- 실패 경로가 `Invalid`를 돌려주고, 생략된 variant는 여전히 구분되는 오류가 된다.
- 기존 값 union 골든이 변하지 않는다.
