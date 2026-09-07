# GOALS

## Problem and the end result from the user's point of view

`.discover = .public` 바인딩은 소스 함수 하나마다 `.exclude` 전체와 `.functions` 전체를 comptime에 다시 훑는다. 넓은 root에서는 `선언 수 × 목록 길이`만큼 comptime 분기를 쓰고, 분기 quota를 키워야 빌드된다. 바인딩당 한 번 만든 색인으로 조회하도록 바꾼다.

## Measurable goals

- `.exclude` 조회가 `std.StaticStringMap` 색인 조회가 된다.
- discovery의 `.functions` 매칭이 경로→항목 위치 색인 조회가 된다.
- 기존 테스트와 예제 전부 통과.

## Supported scope and non-goals

comptime 루프만 다룬다. coverage.zig의 런타임 선형 스캔(`contains`, `publicTypeNamed`)과 타입 키 조회(`registeredTypeName`)는 비목표.

## Reference source / commit / license

`walk.boundFunctionPaths`(38e9a254)와 같은 패턴.

## Completion criteria for the whole plan

두 색인이 들어가고 `zig build test`와 예제 coverage가 통과한다.
