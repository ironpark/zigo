---
depends_on:
- "193-composite-session-handles#3"
perf_phase: false
status: planned
---
> DONE-WHEN: 위 문서 세 곳과 CHANGELOG가 갱신되어 있다.
> NEXT: none

# 문서와 CHANGELOG

## Planned Work

- `docs/authoring/objects-and-lifetimes.md`의 "부모에 속한 child 핸들" 절 뒤에 세션
  절을 추가한다. 선언, 생성 Go, 호출 예와 닫는 순서 계약을 적는다. 메서드 포워딩을
  하지 않는다는 점과 그때 쓸 대안(`zigo.interface`, `satisfies`)을 밝힌다.
- `docs/reference/binding-api.md`의 "패키지와 인터페이스" 절에 `zigo.session`을 넣는다.
- `docs/reference/generated-go-api.md`에 세션 타입의 생성 규칙과 `Close` 계약을 적는다.
- `CHANGELOG.md`의 `Unreleased`에 Added 항목을 쓰고 ABI가 바뀌지 않는다는 점을 밝힌다.
- 문서 안의 link와 anchor를 검사한다.

## Done When

- 위 문서 세 곳과 CHANGELOG가 갱신되어 있다.
- 문서의 선언 조각과 생성 Go가 phase 3의 실제 결과와 일치한다.
- link 검사가 깨끗하다.
