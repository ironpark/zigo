---
depends_on:
- "192-go-functional-options#5"
perf_phase: false
status: planned
---
> DONE-WHEN: 위 문서 네 곳과 CHANGELOG가 갱신되어 있다.
> NEXT: none

# 문서와 CHANGELOG

## Planned Work

- `docs/authoring/values-and-data.md`에 옵션 생성자 절을 추가한다. 대상, 선언 조각,
  생성 Go, 호출 예를 순서대로 적고 기본값이 있는 필드만 옵션이 된다는 규칙을 말한다.
- `docs/reference/binding-api.md`의 계약 도우미 표에 `zigo.param.options`와
  `.type_name`, `.prefix`를 넣는다.
- `docs/reference/generated-go-api.md`에 옵션 타입과 `With*`의 생성 규칙을 적는다.
- `docs/reference/support-matrix.md`에 지원 필드 타입을 반영한다.
- `CHANGELOG.md`의 `Unreleased`에 Added 항목을 쓴다. ABI가 바뀌지 않는다는 점을 밝힌다.
- 문서 안의 link와 anchor를 검사한다.

## Done When

- 위 문서 네 곳과 CHANGELOG가 갱신되어 있다.
- 문서의 선언 조각과 생성 Go가 phase 5의 실제 결과와 일치한다.
- link 검사가 깨끗하다.
