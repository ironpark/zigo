---
completed_at: "2026-09-12T05:08:59Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test`가 새 케이스를 포함해 통과한다.
> NEXT: none

# 기본 접두사와 혼합 시그니처 골든

## Planned Work

- `tests/generator_cases/`에 옵션 골든 케이스를 추가합니다. `semantic.json`에 `.prefix`를
  지정하지 않은 옵션 매개변수와 그 앞의 위치 매개변수를 둔 생성자를 넣어 기본 이름과 혼합
  시그니처를 한 케이스에서 고정합니다. 케이스 이름은 기존 `flattened_options`와 구분되는
  것으로 정합니다.
- 같은 케이스에 소유 타입이 없는 free 함수의 옵션 매개변수도 넣어, 기본 접두사가 함수
  이름에서 오는 경우(`ConfigureOption`)까지 골든으로 덮습니다.
- `options.json`은 기존 케이스의 형태를 따르고, `scripts/update-generator-cases.sh <case>`로
  `expected/`를 만든 뒤 diff를 검토합니다(골든 변경은 생성 코드 변경입니다).
- `build/tests.zig`의 godoc audit 목록에 새 케이스를 등록합니다.
- 골든에서 확인할 것: 기본 접두사 옵션 타입(`TerminalOption`), 비공개 설정 구조체
  (`terminalOptions`), `WithTerminalRows` 형태의 생성자, `opts ...TerminalOption` 가변
  인자, 그리고 그 앞에 남는 위치 인자.

## Done When

- `zig build test`가 새 케이스를 포함해 통과한다.
- 새 골든의 생성 Go에 기본 접두사 옵션 타입, `With*` 생성자, 가변 인자 생성자와 앞선 위치
  인자가 함께 나타난다.
- `.prefix = ""`를 쓰는 07 예제와 `.flatten`을 쓰는 `flattened_options` 케이스의 골든이
  바뀌지 않는다.
