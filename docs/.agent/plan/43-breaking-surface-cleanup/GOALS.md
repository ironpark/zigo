# GOALS

## Problem and the end result from the user's point of view

기능이 하나씩 추가되며 같은 것을 두 가지 방법으로 표현하는 축이 여럿 생겼다. 사용자는
`addGoBindings` 옵션에서 불가능한 조합(`purego` + `static`)을 런타임 `@panic`으로 배우고,
`bindings.zig`에서 같은 메타데이터를 두 문법으로 붙이며, 생성된 Go에서 네 가지 에러 판별
방식을 외워야 한다. 표면을 한 번 깨서 축을 정리하고, 이후에는 안정 계약으로 유지한다.

## Measurable goals

- 표현 불가능한 옵션 조합이 타입 수준에서 사라져 `addGoBindings`의 `@panic` 검증이 줄어든다.
- `bindings.zig`가 선언을 지칭하는 방법이 하나가 된다.
- 소비되지 않는 IR 산출물과 그 배선이 사라진다.
- 생성된 Go의 에러 판별 방식이 하나의 규칙으로 설명된다.

## Supported scope and non-goals

- 범위: `addGoBindings` 옵션, `zigo.define` DSL, reflector CLI, 생성된 Go 공개 표면,
  그리고 그에 따른 문서·예제·테스트 갱신.
- 비범위: C ABI 심볼 규칙과 하강 규칙 변경. 새 기능 추가. 성능 최적화.

## Reference source / commit / license

`build.zig`, `src/reflect/walk.zig`, `src/reflect/main.zig`, `src/gen/emit.zig`,
`docs/.agent/design/05-implementation-status.md`.

## Completion criteria for the whole plan

예제 10종이 새 표면으로 갱신되어 두 백엔드에서 통과하고, 문서가 정리된 축만 서술하며,
마이그레이션 안내가 남는다.
