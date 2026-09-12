---
depends_on:
- "196-options-required-fields#0"
perf_phase: false
status: planned
---
> DONE-WHEN: `zig build test`가 통과한다.
> NEXT: none

# 혼합 시그니처 방출

## Planned Work

- `src/gen/emit/public.zig`에서 필드의 출처를 고르는 판단을 한곳으로 모읍니다. 지금
  `is_options`가 매개변수 단위로 내리는 결정을 필드 단위(`is_options and field.default != null`)로
  바꾸고, 그 판단을 `optionsFieldSourceAlloc` 같은 helper 하나에 둡니다. 대상은 optional raw
  setup(`public.zig:560`), raw 호출 인자(`public.zig:678`), range check(`public_writers.zig:209`)
  세 곳입니다.
- `writePublicParameters`가 옵션 매개변수의 기본값 없는 필드를 위치 인자로 쓰도록 고칩니다.
  이름과 타입은 `.flatten`이 쓰는 것과 같고, 가변 인자 `opts ...`는 그 뒤에 붙습니다.
- `writePublicCallArguments`(`public.zig:1112` 근처)가 같은 필드를 실제 인자로 넘기도록 맞춥니다.
- `renderFunctionOptions`와 `renderFunctionOptionsInit`이 기본값 있는 필드만 설정 구조체,
  `With*` 생성자, `cfg` 초기화에 넣도록 좁힙니다.
- godoc 주석이 남는 자리를 확인합니다. 옵션 타입 주석은 그대로이고, 위치 인자가 된 필드는
  `With*` 주석을 만들지 않습니다.
- 메서드 수신자 이름 계산(`common.zig:551`)이 위치 인자가 된 필드 이름과 충돌하지 않는지
  확인하고, 필요하면 그 목록에 포함시킵니다.
- `src/gen/plugins/must.zig`의 옵션 처리(`must.zig:62`)가 혼합 시그니처의 `Must*` 래퍼를
  올바른 인자 목록으로 내는지 확인하고 맞춥니다.

## Done When

- `zig build test`가 통과한다.
- 혼합 선언에서 생성된 Go 함수가 `func F(<필수 필드들>, opts ...FOption)` 모양이고, 설정
  구조체와 `With*`에는 기본값 있는 필드만 나타난다.
- raw 호출이 위치 인자는 Go 매개변수에서, 옵션은 `cfg.<field>`에서 읽는다.
- 필수 필드의 optional raw setup과 range check가 위치 인자 이름을 쓴다.
- 기존 `functional_options`·`flattened_options` 골든이 바뀌지 않는다.
