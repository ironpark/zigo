# GOALS

## Problem and the end result from the user's point of view

Ultrasync에서 0.1.0 생성물을 쓰며 보고한 네 가지를 코드로 확인했다.
1. 패키지 doc fallback이 `bindings.zig`의 `//!`를 읽는다(`src/reflect/names.zig:18 containerDocAlloc(bindings_source)`). 그 주석은 선언 파일 자신에 대한 설명이라 Go 패키지 doc으로 부적절하다. 같은 함수가 `root_path`도 읽으므로(`:25`) 라이브러리 루트 모듈의 `//!`가 올바른 fallback이다.
2. `runtime.KeepAlive` defer가 잉여다. `defer x.zigoRelease()`가 defer 시점에 `x`를 평가하고 native 호출 뒤 역참조하므로 handle을 함수 끝까지 붙잡는다. `renderKeepAliveDefers`(`src/gen/emit.zig:4452-4464`)와 union accessor 세 템플릿(`:3231, :3970, :4003`)이 handle마다 한 줄씩 더 낸다.
3. `.written = .return`인 out 슬라이스에서 shim이 같은 값을 반환값과 `_written` out 파라미터 두 곳에 쓰고, raw 계층은 `dstWritten`을 선언만 하고 버린다(`examples/07-event-queue/go/bridge/cgo/cgo_gen.go:333-341`). 계획 64가 "C 시그니처 유지, `.all → .return` non-breaking"으로 정한 결과다. 두 값이 다를 수 있는 경우가 없으므로 `.return`은 `_written`을 시그니처에서 빼는 것이 맞고, 그러면 `.all ↔ .return`은 정직하게 breaking이다.
4. error union 반환 함수마다 `runtime.LockOSThread()`(`emit.zig:2715`). `errorForCode`가 패닉 메시지를 native thread-local(`emit.zig:407-418`의 `_Thread_local char zg_panic_message[1024]`)에서 두 번째 cgo 호출(`{prefix}_last_error_message`)로 읽기 때문에 필요하다. 비용은 호출당 수십 ns 이하로 추정되나 측정된 적이 없다. 대안은 모두 ABI 변경이며, Go가 버퍼 포인터를 넘기는 설계는 cgo·purego 인자 escape 때문에 호출당 힙 할당이 생겨 오히려 비쌀 수 있다.

작업 후: 패키지 doc은 옵션 → 루트 모듈 `//!` → 기본 문장 순으로 결정된다. handle 획득 경로에 `KeepAlive`가 없다. `.return` out 슬라이스의 C 시그니처에 `_written`이 없고 raw에 버려지는 변수가 없다. `LockOSThread` 비용이 벤치마크로 기록되고, 유의미할 때만 ABI를 바꾼다.

## Measurable goals

- 01-scalar 골든이 루트 모듈 `//!`에서 패키지 doc을 가져오고, `bindings.zig`의 `//!`는 무시된다는 테스트.
- 공개 생성물에서 `defer runtime.KeepAlive(<handle>)`이 0개(`Close`의 `KeepAlive`와 문자열·슬라이스 데이터 `KeepAlive`는 유지).
- `.return` fixture의 헤더·shim에 `_written` 파라미터가 없고, raw cgo·purego에 `Written` 변수가 없다. `.all ↔ .return`이 abi_diff에서 breaking.
- `LockOSThread` 유무의 호출당 비용 차이가 Go 벤치마크로 `docs/`에 기록된다.

## Supported scope and non-goals

지원: `src/reflect/names.zig`, `src/gen/{emit,lower,abi_diff}.zig`, 골든·예제, 문서, 벤치마크.
비목표: 패닉 메시지 전달 ABI의 실제 변경은 벤치마크 결과가 조건을 만족할 때만(phase 4 conditional). `.written` 의미 자체의 변경. 버전 태그(별도 지시).

## Reference source / commit / license

- Ultrasync 보고(사용자 전달). 계획 64·65의 결정을 일부 되돌린다: 64의 "`_written` 유지·non-breaking", 65의 "`bindings.zig` `//!` fallback".

## Completion criteria for the whole plan

- 측정 목표 테스트 통과. `zig build test --summary all`, `zig fmt --check build.zig src tests examples`, 예제 10개 cgo·purego 4개 `go-check`·`abi-check`·`go vet`·`go test`.
- `docs/bindings.md`(패키지 doc 소스, `.written`의 ABI 영향), `docs/generated-code.md`(KeepAlive 제거, `_written`), `docs/limitations.md`(LockOSThread 비용 기록) 갱신.
