# GOALS

## Problem and the end result from the user's point of view

같은 generic에서 나온 handle(`IntBatch`, `FloatBatch`)이나 같은 vtable을 채우는 구현체들은 Go에서
서로 무관한 타입이다. 사용자가 `zigo.define`에 `.interfaces = .{ .{ .name, .methods, .types } }`를
적으면 zigo가 그 타입들이 그 메서드를 같은 Go 시그니처로 제공하는지 검증하고, Go 인터페이스와
`var _ Iface = (*T)(nil)` 단언을 `<pkg>_interfaces_gen.go`에 낸다. `anytype` duck typing과 Go
generic은 다루지 않는다. 설계는 `docs/.agent/design/11-comptime-interfaces.md` 2절.

## Measurable goals

- `Semantic.interfaces`가 직렬화·역직렬화되고, 등록하지 않은 바인딩의 `semantic.json`과 생성물은
  바이트 동일하다(golden 44개 불변).
- ZIGO049가 설계 2.4의 규칙 1~6을 그 순서로 보고하고 스냅샷 테스트가 있다.
- golden case `interfaces`, `interfaces_purego`가 `<pkg>_interfaces_gen.go`를 담고 `go vet`
  단계를 통과한다.
- `examples/05-pipeline`이 `Batch` 인터페이스를 내고 예제 Go 테스트가 통과한다.
- `abi-diff`가 인터페이스 추가를 added, 제거·메서드 변경을 breaking으로 보고한다.

## Supported scope and non-goals

- 범위: `src/reflect/walk.zig`, `src/gen/ir/{semantic,abi}.zig`, `src/gen/validate/`,
  `src/gen/lower.zig`, `src/gen/emit/`, `src/gen/generator.zig`, `src/gen/abi_diff.zig`,
  golden case 2개, 예제 05, `docs/bindings.md`, `docs/limitations.md`, CHANGELOG.
- 비범위: `anytype` specialization, Go generic 제약, vtable struct 자동 반영, 인터페이스를 파라미터로
  받는 함수, `ir_version` 변경.

## Reference source / commit / license

- `docs/.agent/design/11-comptime-interfaces.md` 2절과 3절.
- 기존 tagged union sealed interface (`public_types.renderPublicUnionVariants`)의 이름 규칙과 파일 배치.
- 계획 109·111이 세운 "lowering이 결정하고 emit은 읽는다", "렌더링해서 비교한다" 규칙.

## Completion criteria for the whole plan

- 네 phase가 커밋되어 `done`이고 `zig build test`가 녹색이다.
- CHANGELOG `[Unreleased]`에 `Added`로 기록되고 minor 릴리즈(`0.9.0`) 대상임이 적혀 있다.
