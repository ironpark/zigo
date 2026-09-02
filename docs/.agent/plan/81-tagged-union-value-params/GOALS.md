# GOALS

## Problem and the end result from the user's point of view

`Terminal.scrollViewport(behavior: ScrollViewport)`처럼 payload가 `void`/`isize`/`usize`뿐인 tagged union을 값으로 받는 파라미터는 `ZIGO006`으로 거부된다. 힌트는 pointer 노출을 권하지만 그것은 반환·projection 축의 이야기다. 현재 우회는 variant마다 함수를 하나씩 두는 것이며 Go에서는 오히려 읽기 좋아 우선순위는 낮다.

끝난 뒤: 등록된 tagged union 중 모든 payload가 스칼라(정수·부동소수·bool·등록 enum) 또는 void인 것은 값 파라미터로 받을 수 있다. C 표면은 `(tag, payload 슬롯…)` 평탄화, Go 표면은 variant별 생성자 함수를 가진 값 타입(`ScrollViewportTop()`, `ScrollViewportDelta(n)`)이다.

## Measurable goals

- 골든: 위 형태의 union을 값 파라미터로 받는 함수가 cgo·purego에서 생성되고 Go 테스트가 각 variant를 호출한다.
- payload가 슬라이스·포인터·struct인 union은 계속 ZIGO006이며 힌트가 두 축을 구분해 안내한다.

## Supported scope and non-goals

- 범위: `validate.zig`(ZIGO006 완화·힌트), `lower.zig`/`emit.zig`(C 평탄화, shim 재조립, Go 값 타입), 골든, 예제 10, 문서, CHANGELOG.
- 비범위: 값 반환, non-scalar payload, 중첩 union.

## Reference source / commit / license

`src/gen/validate.zig:130-190, 284`(ZIGO006), tagged union snapshot/projection 구현(`emit.zig` `Snapshot`/`Variant`), 예제 `10-tagged-union`. gostty `docs/zigo-findings.md` C. 라이선스 변경 없음.

## Completion criteria for the whole plan

모든 phase done, `zig build test`·`zig fmt --check`·전 예제 cgo+purego 녹백, CHANGELOG Unreleased Added.
