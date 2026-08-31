# GOALS

## Problem and the end result from the user's point of view

설계 문서는 "값으로 넘기고 싶으면 `extern struct`로 선언하라"고 안내하지만 그 경로는
구현되어 있지 않다. `.repr = .value`로 등록한 extern struct를 파라미터로 쓰면 reflector와
validate를 통과한 뒤 `src/gen/lower.zig`의 `else => unreachable`에서 generator가 패닉한다.
사용자는 config·Rect 같은 평범한 구조체를 Go에서 값처럼 주고받을 수 있어야 한다.

## Measurable goals

- `extern struct` 파라미터와 반환이 진단 없이 하강되어 cgo와 purego 양쪽에서 동작한다.
- 부적격 struct는 패닉이 아니라 선언 위치와 수정 방법을 담은 진단으로 거부된다.
- Go 공개 API는 값 타입(`func Configure(cfg Config) error`)으로 노출된다.
- `zigo-gen`에 도달 가능한 `unreachable` 경로가 이 영역에서 사라진다.

## Supported scope and non-goals

- 범위: `value_struct`의 하강과 emit, 적격 조건과 진단, ABI diff 규칙, 예제와 문서.
- 비범위: `packed struct`의 정수 백킹 노출. 일반 struct의 값 노출. C 경계에서 aggregate를
  값으로 전달하는 방식. tagged union snapshot 표현 변경.

## Reference source / commit / license

현재 브랜치의 `src/gen/{lower,emit,validate,abi_diff}.zig`, `src/reflect/walk.zig`,
`src/gen/ir/semantic.zig`. 재현: `value_struct` 파라미터를 가진 semantic 문서로
`zigo-gen generate` 실행 시 `lower.zig:386` 패닉.

## Completion criteria for the whole plan

예제가 extern struct를 값 의미로 주고받고, 두 백엔드 테스트가 통과하며, 적격성 진단과
ABI 규칙에 테스트가 있고, 설계 문서가 포인터 전달 규칙을 서술한다.
