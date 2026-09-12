---
depends_on:
- "196-options-required-fields#1"
perf_phase: false
status: planned
---
> DONE-WHEN: `zig build test`가 새 케이스를 포함해 통과한다.
> NEXT: none

# 골든과 문서

## Planned Work

- `tests/generator_cases/`에 혼합 선언 케이스를 추가합니다. 한 생성자에 기본값 없는 필드
  두 개와 기본값 있는 필드 두 개를 두고, range check가 필요한 좁은 정수와 optional 필드를
  섞어 위치 인자·옵션 양쪽의 검사 코드를 함께 고정합니다.
- 같은 케이스에 소유 타입이 없는 free 함수 하나를 넣어 기본 접두사(`ConfigureOption`)와
  혼합 시그니처가 함께 나오는 것을 덮습니다.
- `scripts/update-generator-cases.sh <case>`로 `expected/`를 만들고 diff를 검토합니다.
  `build/tests.zig`의 godoc audit 목록에 새 케이스를 등록합니다.
- `docs/authoring/values-and-data.md`의 옵션 절을 새 규칙으로 고칩니다. 기본값이 필수가
  아니라 필드를 위치 인자와 옵션으로 나누는 기준이라는 것, 나열되지 않은 필드는 여전히
  기본값을 가져야 한다는 것, 그리고 `.flatten`과 언제 갈리는지를 적습니다.
- `docs/reference/generated-go-api.md`의 functional options 절에 혼합 시그니처를 추가합니다.
- `CHANGELOG.md`의 `Unreleased`에 항목을 적습니다.

## Done When

- `zig build test`가 새 케이스를 포함해 통과한다.
- 새 골든의 생성 Go에 위치 인자, 옵션 타입, `With*` 생성자, `opts ...` 가변 인자가 함께
  나타나고 설정 구조체에는 기본값 있는 필드만 있다.
- 새 케이스가 godoc audit을 통과한다.
- 문서 두 곳의 선언 조각과 생성 Go가 실제 결과와 일치하고 링크 검사가 깨끗하다.
- `CHANGELOG.md`에 항목이 있다.
