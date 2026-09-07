# GOALS

## Problem and the end result from the user's point of view

`.param_meta`의 키가 `.params`에 없으면(또는 `.params` 자체가 없으면) 메타데이터가 조용히 사라져 ABI 방향·semantic 힌트가 뒤집힌다. 또 `double` 같은 C 예약어가 파라미터 이름으로 그대로 헤더에 나가 C 컴파일이 깨진다. 두 경우 모두 생성 단계에서 명확한 진단으로 거부되어야 한다.

## Measurable goals

- `.param_meta` 키가 `.params`에 없으면 reflection이 `ZIGO057`로 거부한다.
- `.param_meta`가 있는데 `.params`가 없으면 같은 진단으로 거부한다.
- C 키워드/표준 typedef 이름인 파라미터는 validation이 `ZIGO021`로 거부한다.

## Supported scope and non-goals

지원: `.params`/`.param_meta` 정합성, C 파라미터 이름 예약어 검사. 비목표: 이름 맹글링, Zig 키워드 검사.

## Reference source / commit / license

`src/reflect/walk.zig`의 ZIGO027 패턴, `src/gen/validate/names.zig`의 `identifierIssue`.

## Completion criteria for the whole plan

두 검사와 테스트가 추가되고 `zig build test`가 통과하며 문서(diagnostics, cheatsheet)가 갱신된다.
