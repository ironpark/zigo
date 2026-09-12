# GOALS

## Problem and the end result from the user's point of view

`zigo.param.options`는 "옵션 구조체의 모든 필드가 Zig 기본값을 가진다"는 규칙만 구현되어
있고, 기본값이 없는 값(예: `cols`)을 어떻게 노출하는지에 대한 답이 코드·문서·테스트 어디에도
없습니다. `ZIGO061`의 hint는 "expose it as a positional parameter"라고 안내하지만
`.options` 안에서 그렇게 할 방법이 없어 사용자를 막다른 길로 보냅니다. 한편 기본 접두사
(`<Type>Option`, `With<Type><Field>`)는 이름 계산 단위 테스트로만 검증되고 실제 방출 경로를
한 번도 지나지 않았습니다. `zigo.param.options` 사용처는 저장소 전체에서 `examples/07-event-queue`
한 줄뿐이고 그마저 `.prefix = ""`입니다.

이 계획이 끝나면 필수 값은 Zig 함수의 별도 매개변수로, 선택 값은 옵션 구조체로 두는 관용구가
진단·문서·예제·골든 네 곳에서 같은 말을 합니다.

## Measurable goals

- `ZIGO061` hint가 실제로 실행 가능한 두 해법(기본값 부여, 별도 매개변수로 이동)을 말한다.
- `examples/07-event-queue`의 생성 시그니처가 `func NewTerminal(initialCols uint16, opts ...Option) (*Terminal, error)`이고 `go test ./...`가 통과한다. 이때 C ABI는 그대로다.
- `.prefix`를 지정하지 않은 선언의 골든이 기본 이름(`TerminalOption`, `WithTerminalRows`)을 방출 결과로 고정한다.
- `.flatten`과 `.prefix = ""`의 기존 골든과 예제 결과는 바뀌지 않는다.

## Supported scope and non-goals

지원 범위는 현재 생성기가 이미 만들 수 있는 형태입니다. 생성기 로직(lowering·shim·방출)은
바꾸지 않습니다.

non-goal:

- 옵션 구조체 **안**의 기본값 없는 필드를 위치 인자로 넘기는 것. shim이 구조체를 flattened
  필드만으로 재조립하므로(`src/gen/emit/shim.zig:828`) 그 필드는 담을 값을 가질 수 없습니다.
  지원하려면 flatten 계약("나열되지 않은 필드는 기본값을 가진다")과 lowering·검증을 함께
  바꿔야 하고, 별도 계획의 몫입니다.
- Rust target, builder 패턴, 여러 매개변수를 한 `Option`으로 묶는 래퍼.
- `.flatten`의 기존 동작 변경.

## Reference source / commit / license

외부 소스를 가져오지 않습니다. 저장소 안의 기존 구현을 참조합니다.

- `src/gen/emit/public.zig:1179` -- 옵션 가변 인자를 마지막에 붙이는 시그니처 작성
- `src/gen/emit/shim.zig:828` -- flattened 필드로 구조체를 재조립하는 지점
- `src/reflect/walk.zig:1198` -- 나열되지 않은 필드의 기본값 존재 검사
- `tests/generator_cases/flattened_options` -- 골든 케이스의 기존 형태
- `scripts/update-generator-cases.sh` -- 골든 재생성

## Completion criteria for the whole plan

모든 phase가 done이고, `zig build test`와 07 예제의 `go-check`/`abi-check`/`go test`가
통과하며, `ZIGO061` hint와 문서와 골든이 같은 관용구를 말합니다.
