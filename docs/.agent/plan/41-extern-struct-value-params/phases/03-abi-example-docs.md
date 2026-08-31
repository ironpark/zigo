---
completed_at: "2026-08-31T10:25:51Z"
depends_on:
- "41-extern-struct-value-params#2"
perf_phase: false
status: done
---
> DONE-WHEN: 필드 변경이 breaking으로 나오는 CLI 계약 테스트가 있다.
> NEXT: none

# ABI rules, example and documentation

## Planned Work

- abi diff가 extern struct의 필드 추가·삭제·순서 변경·타입 변경을 breaking으로 판정하게 한다.
- 예제에 extern struct 파라미터와 반환을 추가하고 두 백엔드로 검증한다.
- `03-lowering-rules.md` §6과 `00-constraints.md` §3의 "값 전달" 서술을 "값 의미, 포인터 전달"로
  고치고, `configuration.md`·`limitations.md`·`05-implementation-status.md`를 갱신한다.

## Done When

- 필드 변경이 breaking으로 나오는 CLI 계약 테스트가 있다.
- 예제가 CI에서 두 백엔드로 빌드·테스트된다.
- 설계 문서가 aggregate를 값으로 넘기지 않는다는 규칙을 한 곳에서 서술한다.
