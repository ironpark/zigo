---
depends_on:
- "197-string-writer-byte-params#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: 문서 세 곳이 코드와 같은 조건을 말하고, 예제 조각이 실제 선언과 일치한다.
> NEXT: none

# 문서

## Planned Work

- `docs/authoring/streams-and-cancellation.md`의 두 kind 비교를 새 규칙으로 고칩니다.
  `.string_writer`는 string semantic을 요구하지 않고, 바이트 매개변수에서는 생성기가 복사
  없이 문자열의 바이트를 빌려 넘긴다는 것과 그 수명 계약을 적습니다. `.writer`에 string
  힌트를 붙이면 왜 여전히 거절되는지도 함께 남깁니다.
- `docs/reference/binding-api.md`의 `.string_writer` 설명을 맞춥니다.
- `docs/reference/diagnostics.md`의 `ZIGO058` 행에서 없어진 조건을 지웁니다.
- `CHANGELOG.md`의 `Unreleased`에 항목을 적습니다.

## Done When

- 문서 세 곳이 코드와 같은 조건을 말하고, 예제 조각이 실제 선언과 일치한다.
- 문서 링크·anchor 검사가 깨끗하다.
- `CHANGELOG.md`에 항목이 있다.
