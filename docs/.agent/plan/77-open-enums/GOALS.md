# GOALS

## Problem and the end result from the user's point of view

Zig에서 흔한 비exhaustive enum(`enum(u8) { a, b, _ }`)은 `ZIGO002`로 거부된다. ghostty는 pty 입력을 `@enumFromInt`로 안전하게 받기 위해 `EraseDisplay`, `EraseLine`, `TabClear`를 이렇게 선언하고, 바인딩 쪽은 같은 이름의 exhaustive enum과 wrapper 세 개로 우회하고 있다. 생성되는 Go enum은 이미 정수 기반 타입 + 명명 상수 + `String()`의 `default` 분기 구조라 알 수 없는 값을 표현할 수 있다.

끝난 뒤: `.types` 항목에 `.exhaustive = false`를 적으면 비exhaustive enum이 그대로 노출되고, Go 호출자가 어떤 정수든 넘길 수 있으며 반환된 미지의 값은 `Name(N)`으로 출력된다. opt-in이 없으면 지금처럼 ZIGO002다.

## Measurable goals

- opt-in을 단 비exhaustive enum이 파라미터·반환·struct 필드·slice 원소로 cgo·purego에서 통과한다.
- opt-in 없는 비exhaustive enum은 계속 ZIGO002이고, exhaustive enum에 `.exhaustive = false`를 달면 진단(ZIGO0xx)이 난다.
- 기존 예제 생성물은 바이트 동일하다.

## Supported scope and non-goals

- 범위: 타입 등록 메타, `walk.zig` 반영, `validate.zig` 완화·새 진단, Go doc 문구, abi_diff, 예제/골든, 문서, CHANGELOG.
- 비범위: 비exhaustive tag를 가진 tagged union(계속 거부), Go 쪽 값 검증(열린 enum이므로 하지 않음).

## Reference source / commit / license

`src/gen/validate.zig:268-274`(ZIGO002), `src/reflect/walk.zig:1077, 1165`(`exhaustive` 반영), `src/gen/emit.zig:5390-5415`(`renderGoEnums`, `default` 분기), `src/gen/emit.zig:761, 883`(shim `@enumFromInt`). 라이선스 변경 없음.

## Completion criteria for the whole plan

모든 phase done, `zig build test`·`zig fmt --check`·전 예제 cgo+purego 녹색, CHANGELOG Unreleased에 Added 기재.
