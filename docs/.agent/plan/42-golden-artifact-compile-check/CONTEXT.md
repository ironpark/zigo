# SCOPE

`build.zig`, `tests/generator_cases/`.

# CONTEXT

## Current implementation and bottlenecks

`addGeneratorCases`는 케이스마다 러너를 실행해 생성 결과와 `expected/` 트리를 텍스트
비교한다. 산출물이 컴파일 가능한지는 어디에서도 확인하지 않는다. shim은 사용자 모듈
`zigo_target`을 import하므로 단독 컴파일이 불가능하지만 파싱은 가능하다.

## Target structure and invariants

- 검사 대상은 생성 결과가 아니라 커밋된 `expected/` 골든이다. 골든이 곧 계약이다.
- C는 `zig cc -fsyntax-only`로, Zig는 `zig ast-check`로 확인한다. 링크나 실행은 하지 않는다.
- 케이스가 추가되면 자동으로 검사에 포함된다. 케이스 목록을 손으로 유지하지 않는다.
