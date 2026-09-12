# GOALS

## Problem and the end result from the user's point of view

`.flatten`으로 선언한 옵션 구조체 매개변수는 지금 선택한 필드 전부가 Go 위치 인자로
펼쳐집니다. `examples/07-event-queue`의 `Terminal.init`은 Zig에서
`cols: u16`, `rows: u16 = 24`, `max_scrollback_bytes: usize = 1024 * 1024`인데
생성 결과는 `func NewTerminal(cols uint16, rows uint16, maxScrollbackBytes uint) (*Terminal, error)`
입니다. Zig가 가진 기본값이 Go 쪽에서 사라져 호출자가 모든 값을 직접 적어야 하고,
필드가 늘어날 때마다 생성자 시그니처가 깨집니다.

이 계획이 끝나면 바인딩 작성자가 `zigo.param.options`로 같은 매개변수를 선언해
Go 관용 표현인 functional options 생성자를 얻습니다.

```go
func NewTerminal(cols uint16, opts ...TerminalOption) (*Terminal, error)
func WithTerminalRows(rows uint16) TerminalOption
func WithTerminalMaxScrollbackBytes(maxScrollbackBytes uint) TerminalOption
```

기본값이 있는 필드는 옵션이 되고, 기본값이 없는 필드(`cols`)는 위치 인자로 남습니다.
호출자는 바꾸고 싶은 값만 적습니다.

## Measurable goals

- `zigo.param.options(index, fields)`로 선언한 매개변수가 위 모양의 Go API를 만든다.
- 같은 함수를 `zigo.param.flatten`으로 선언하면 생성 결과가 지금과 byte 단위로 같다.
- 옵션 도입 전후로 `zig build abi-check`가 차이를 보고하지 않는다: C 심볼, 매개변수
  개수와 순서가 모두 그대로다.
- 기본값이 없는 필드를 옵션으로 지정하면 진단으로 거절된다.
- `examples/07-event-queue`가 옵션 생성자를 쓰고 Go 테스트가 통과한다.

## Supported scope and non-goals

지원 범위는 이미 `.flatten`이 허용하는 필드 타입(bool, 정수, 실수, 등록 enum,
등록 packed value, optional 스칼라)과 Go 출력 target입니다.

non-goal:

- Rust target. `Parameter.go`에만 정보를 얹으므로 Rust는 이 매개변수를 지금처럼
  위치 인자로 봅니다. builder 패턴은 별도 계획입니다.
- 구조체가 아닌 매개변수, 중첩 구조체 필드, 슬라이스·문자열 필드.
- `.flatten`의 기존 동작 변경. 옵션화는 opt-in이며 기본 동작은 그대로입니다.
- 함수 전체를 옵션으로 감싸는 일반 래퍼(여러 매개변수를 한 `Option`으로 묶기).

## Reference source / commit / license

외부 소스를 가져오지 않습니다. 저장소 안의 기존 구현을 참조합니다.

- `src/gen/emit/shim.zig:828` -- 선택 필드로 Zig 구조체를 되조립하는 현재 shim
- `src/gen/lower.zig:101` -- 필드마다 ABI 매개변수를 까는 lowering
- `src/gen/plugins/must.zig:36` -- 생성 이름 충돌을 `ZIGO024`로 보고하는 선례
- `src/reflect/walk.zig:1160` -- 선택하지 않은 필드의 기본값 존재 검사

## Completion criteria for the whole plan

모든 phase가 done이고, `scripts/release.sh`가 실행하는 검사(`zig fmt --check`,
`zig build test`, 예제 `go-check`/`rust-check`/`abi-check`, staticcheck)가 통과하며,
`docs`와 `CHANGELOG.md`가 새 authoring API를 설명합니다.
