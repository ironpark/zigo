# GOALS

## Problem and the end result from the user's point of view

`.discover = .public` 반영은 발견한 함수마다 `.functions`와 `.exclude`를 comptime 색인으로 조회한다. 조회는 빠르지만 여전히 comptime이라 분기 quota와 메모이즈 순서에 묶인다. 목록 항목은 명시 바인딩과 같은 경로로 먼저 반영하고, 탐색 패스는 런타임 해시 집합으로 "이미 반영됐거나 제외됐는가"만 묻게 바꿔 comptime에는 선형 루프만 남긴다.

## Measurable goals

- `boundFunctionPaths`, `excludedPaths`, `appendDiscoveredEntry`가 사라진다.
- discovery와 coverage의 경로 조회가 런타임 `StringHashMap`이 된다.
- 전체 테스트와 예제 go-check가 통과한다.

## Supported scope and non-goals

문서의 함수 순서가 "목록 항목 먼저, 발견 함수 다음"으로 바뀌는 것은 허용한다. 타입 키 comptime 조회(`registeredTypeName` 등)는 비목표.

## Reference source / commit / license

`checkDeclaredPaths`의 런타임 집합 패턴, `appendSelectedEntry`의 항목 주도 반영.

## Completion criteria for the whole plan

두 phase 완료, 08-telemetry-hub 생성물 재생성, CHANGELOG 갱신.
