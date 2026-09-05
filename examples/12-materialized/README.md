# 중첩 결과를 Go 값으로 받기

native 객체의 필드를 하나씩 호출해 읽는 대신 string·slice·중첩 포인터를 포함한 결과를
한 버퍼로 받아 Go 값 트리로 디코딩합니다. [실행 가능한 사용 예제](go/materialized/example_test.go)에서
`Snapshot`의 필드 접근과 재사용할 출력 slice의 `Fill`을 먼저 확인하세요.

## 실행

이 디렉터리에서 실행합니다.

```sh
zig build go
(cd go && go test -run '^Example' -v ./...)
(cd go && go test ./...)
zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

## 어떤 반환 방식을 쓸까요?

| API | 용도 |
|---|---|
| `Snapshot() Probe` | 한 개의 중첩 결과 |
| `ProbeMany() ([]Probe, error)` | 배치 반환과 오류 처리 |
| `Fill([]Probe) uint` | Go 출력 slice를 제공하고 작성 개수 확인 |
| `NewLegacyProbe`와 accessor | handle 방식의 수명·호출 비용 비교 |

materialized 결과는 Go 소유 값입니다. 반환값에 `Close`할 필요가 없고 native 결과 버퍼는
생성 코드가 release합니다. 반면 `LegacyProbe`는 명시적으로 닫아야 합니다.
[바인딩 선언](src/bindings.zig)의 allocator, `.materialized`, `.returns = .caller`,
`[]u8` release 함수는 함께 옮겨야 합니다.

`Fill`은 Go slice 자체를 재사용하지만 중첩 데이터의 할당이나 native 직렬화 버퍼까지
없애는 zero-allocation API는 아닙니다.

## 성능 비교

```sh
(cd go && go test -run '^$' -bench 'Benchmark(MaterializedDecode|AccessorHandles)$' -benchmem ./materialized)
```

두 benchmark는 동일한 필드 전체를 읽는 비교가 아닙니다. accessor는 일부 필드만 읽으므로
출력 숫자를 보편적인 배속으로 해석하지 마세요. 자신의 결과 크기·필드 접근 패턴으로
측정해야 합니다.

[결과 타입 가이드](../../docs/bindings-types.md) · [버퍼 ABI](../../docs/abi.md) · [전체 예제](../../docs/examples.md)
