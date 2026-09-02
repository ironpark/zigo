---
perf_phase: false
status: in-progress
---
> DONE-WHEN: 취소 테스트 통과, 취소 없는 함수의 골든 불변.
> NEXT: none

# 취소 규약

## Planned Work

- 설계 결정(Go 소유 플래그 vs 폴링 함수 포인터) 기록. `.cancel` 메타, 검증, lowering, shim, Go `ctx` 래퍼와 감시 goroutine, `context.Canceled` 매핑.
- 예제(08-telemetry-hub 또는 11)에 긴 호출과 취소 테스트. 문서.

## 설계 결정: Go가 소유하는 플래그

**Go 소유 플래그를 골랐다.** 폴링 함수 포인터와 비교한 근거:

1. **폴링 비용이 0이다.** 플래그 폴링은 원자적 load 하나이고 경계를 넘지 않는다. Zig 쪽이
   내부 루프에서 아무리 촘촘히 검사해도 공짜다. 함수 포인터라면 폴링마다 Go로 되돌아가야
   하는데, 취소 검사는 자주 하는 것이 본질이므로 정확히 반대 방향의 비용이다.
2. **ABI가 인자 하나다.** 함수 포인터는 포인터 + userdata 두 인자이고, purego에서는
   dispatcher까지 하나 더 필요하다. 플래그는 `const uint32_t *` 하나로 끝난다.
3. **Go 메모리 규칙을 만족한다.** 워드는 Go 포인터를 담지 않고, 주소는 호출 동안만
   빌려준다 — cgo가 명시적으로 허용하는 형태다.

## Implementation Notes

**플래그 타입은 `*const std.atomic.Value(u32)`다.** CONTEXT는 `Value(bool)`/`uint8_t`를
스케치했지만 그것은 Go 쪽에서 성립하지 않는다: 플래그는 native가 읽는 동안 다른
goroutine이 쓰므로 원자적 쓰기가 필요한데, Go의 `sync/atomic`은 32비트에서 시작하고
1바이트를 원자적으로 쓸 방법이 없다. `atomic.Bool`의 내부 레이아웃은 비공개이고
`uint8`도 아니다. `extern struct { raw: u32 }`와 Go `uint32`는 지원하는 모든 타깃에서
같은 4바이트라, 어느 쪽도 상대의 레이아웃을 짐작하지 않는다. **CONTEXT에서 벗어난 유일한
지점이며, 이유는 위와 같다.**

**표현.** 새 `TypeNode.cancel_flag`와 새 `AbiParam.Role.cancel_flag`. `param_meta`가 아니라
함수 메타(`SemanticFn.cancel`)이고, 파라미터에는 `Parameter.cancel` 표시가 붙는다. 둘로
나눈 이유는 진단이다: 이름이 아무 파라미터에도 닿지 않는 경우를 함수 쪽에서 잡아야 한다.
`walk.zig`는 메타가 그 이름을 부를 때만 `*const std.atomic.Value(u32)`를 특별 취급하므로,
그렇지 않은 곳에서는 예전처럼 "등록되지 않은 struct 포인터"로 거부된다.

**생성된 Go.** `ctx context.Context`가 첫 인자. 호출 프레임의 `var zigoCancel uint32`를
`ctx.Done()` 감시 goroutine이 `atomic.StoreUint32`로 세우고, `defer close(zigoStop)`으로
호출이 끝나면 goroutine을 정리한다. 취소될 수 없는 ctx는 goroutine을 만들지 않고, 이미
취소된 ctx는 호출 전에 플래그를 세운다(native는 여전히 호출되고 첫 폴링 지점에서 멈춘다).
cgo는 C에 넘긴 Go 포인터를 호출 동안 고정하지만 purego에는 그 보장이 없으므로 purego
백엔드에서만 `runtime.Pinner`로 고정하고 raw가 `runtime.KeepAlive`한다.

**error 매핑.** error set에 `Canceled`가 있어야 한다(`ZIGO026`). native가 `Canceled`를
돌려주고 `ctx.Err() != nil`이면 `ctx.Err()`를 반환하므로 `context.Canceled`와
`context.DeadlineExceeded`가 구분된다. ctx가 멀쩡한데 native가 `Canceled`면 그것은
라이브러리의 error이므로 `ErrCanceled`가 그대로 나온다.

**`abi_diff`의 error set 비교를 위치 기반에서 멤버십 기반으로 바꿨다.** 예제 08에 error
set 하나를 추가하자 Zig reflection이 무관한 `QueryError`의 순서를 뒤집었고, 위치 비교는
그것을 "error removed or error code reassigned"로 봤다. 실제로는 코드가 하나도 바뀌지
않았다 — 코드는 `semantic.json`과 함께 다니는 `errors.lock.json`이 이름별로 고정한다.
빠진 이름은 여전히 breaking, 늘어난 이름은 여전히 compatible이다.

예제 08에 `TelemetryHub.reduce`를 추가하고, 취소 없는 완주·미리 취소된 ctx·실행 중 취소·
deadline 네 가지를 cgo·purego 양쪽에서(`-race` 포함) 테스트한다. 골든
`cancel{,_purego}`는 `.cancel`이 붙은 함수와 붙지 않은 함수를 한 문서에 담아, 후자의
생성물이 그대로임을 함께 고정한다.

## Done When

- 취소 테스트 통과, 취소 없는 함수의 골든 불변.
