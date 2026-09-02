# GOALS

## Problem and the end result from the user's point of view

`fn freeTerminal(gpa: Allocator, self: *Terminal) void`처럼 주입 파라미터가 handle보다 앞에 오면 `receiverName`이 `params[0]`만 보므로 메서드로도, `.destroys` 대상으로도 인식되지 않는다(ZIGO028). 끝난 뒤에는 주입 파라미터를 건너뛴 첫 handle 파라미터가 receiver가 된다.

## Measurable goals

- allocator-first 소멸자와 allocator-first 메서드가 receiver로 잡히고 shim이 Zig 선언 순서대로 호출한다.

## Supported scope and non-goals

- 범위: walk.zig receiver 판정, emit.zig shim 인자 순서, 골든, 문서. 비범위: 파라미터 재배열 메타.

## Reference source / commit / license

`src/reflect/walk.zig:1000`, `src/gen/emit.zig:694`. 라이선스 변경 없음.

## Completion criteria for the whole plan

테스트·fmt·전 예제 녹색, CHANGELOG Unreleased 기재.
