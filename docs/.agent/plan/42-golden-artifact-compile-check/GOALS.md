# GOALS

## Problem and the end result from the user's point of view

generator case 테스트는 산출물을 텍스트로만 비교한다. 그래서 컴파일되지 않는 `panic.c`가
골든으로 고정되어도 통과한다. 실제로 `value_struct` 골든이 헤더 include를 빠뜨린 채
커밋되었고, 뒤이은 예제 작업이 우연히 발견했다. 예제가 다루지 않는 조합은 계속 통과한다.
생성기가 문법적으로 깨진 네이티브 산출물을 내면 테스트가 즉시 실패해야 한다.

## Measurable goals

- 모든 generator case의 골든 `panic.c`가 헤더와 함께 컴파일된다.
- 모든 generator case의 골든 `shim.zig`가 파싱된다.
- 헤더 include를 지운 골든이 실제로 실패하는 것을 확인한다.

## Supported scope and non-goals

- 범위: `build.zig`의 generator case 배선과 필요한 테스트 도구.
- 비범위: 생성된 Go 파일의 컴파일 검증(Go 툴체인 의존). shim의 의미 검사(사용자 모듈이
  없으면 불가능). 예제 검증 변경.

## Reference source / commit / license

`build.zig`의 `addGeneratorCases`, `tests/generator_case_main.zig`,
`tests/generator_cases/*/expected/`.

## Completion criteria for the whole plan

`zig build test`가 골든의 C 컴파일과 Zig 파싱을 포함하고, 고의로 깨뜨린 골든에서 실패한다.
