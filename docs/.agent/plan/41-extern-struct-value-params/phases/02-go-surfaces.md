---
completed_at: "2026-08-31T10:18:43Z"
depends_on:
- "41-extern-struct-value-params#1"
perf_phase: false
status: done
---
> DONE-WHEN: 두 백엔드가 같은 공개 API를 제공하고 테스트가 통과한다.
> NEXT: none

# Go surfaces for both backends

## Planned Work

- cgo raw와 purego raw에 포인터 시그니처를 낸다.
- public Go는 값 타입으로 노출하고 호출부에서 주소를 잡는다. 반환은 out 파라미터를 채운 뒤
  값으로 돌려준다.
- Go 구조체 미러의 필드 순서와 타입이 헤더와 일치함을 테스트로 고정한다.

## Done When

- 두 백엔드가 같은 공개 API를 제공하고 테스트가 통과한다.
- Go 포인터 규칙 위반 없이 struct가 왕복한다.
