# 상태를 가진 이벤트 큐

용량 제한이 있는 Zig 이벤트 큐를 Go 패키지로 노출합니다. 객체 수명뿐 아니라 값 타입,
버퍼, 하위 패키지를 함께 확인할 때 사용하는 예제입니다.

## 확인할 기능

| 기능 | 이 예제의 API |
|---|---|
| 객체 수명과 retained observer | `EventQueue`, `Close`, 수명 카운터 |
| enum 정책과 typed error | `reject`·`drop_oldest`, 용량 오류 |
| extern struct 값 전달 | `Stats`, `Limits`, `ApplyLimits` |
| struct slice 입력·출력·반환 | `AcceptStats`, `Estimate`, `SampleStats` |
| NUL 종료 문자열 | `EchoCString`, `SampleCString` |
| 문자열 slice | `ExtractPaths`, `ExtractSentinelSlices`, `ExtractSentinelPointers` |
| caller-owned slice와 release | `ExtractSamples`, `freeSamples`, `LiveSamples` |
| allocator 주입 | `freeLimits` |
| 타입 밖의 생성자·소멸자 | `.constructs`·`.destroys`로 등록한 `Ticker` |
| 하위 패키지 간 참조 | `event_queue/types`의 `Ticker`, `TickerInfo`, 열린 enum |

raw cgo 패키지는 `go/bridge/cgo`에 둡니다. `Stats`·`Limits`는 공개 Go에서 값으로
사용하지만 C 경계에서는 포인터로 전달합니다. `go/bridge/cgo/cheader`를 사용하는 테스트가
생성 헤더와 Go 표현의 레이아웃을 비교합니다.

## 실행

이 디렉터리에서 실행합니다.

```sh
zig build test go-check abi-check
zig build go
(cd go && go test -count=1 ./...)

zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test -count=1 ./...)
```

## 수명과 동시 호출 주의사항

`EventQueue` 자체는 스레드 안전하지 않습니다. 동시성 테스트도 goroutine마다 별도의 큐를
만듭니다. 같은 큐를 공유하려면 호출자가 동기화해야 합니다.

caller-owned handle의 `runtime.AddCleanup` 안전망은 강제 GC 테스트로 확인합니다.
실행 시점을 보장하지 않으므로 애플리케이션은 여전히 명시적으로 `Close`해야 합니다.

선언 규칙은 [객체 수명](../../docs/bindings-handles.md)과
[문자열과 버퍼](../../docs/bindings-buffers.md), 전체 목록은
[예제 선택 가이드](../../docs/examples.md)를 참고하세요.
