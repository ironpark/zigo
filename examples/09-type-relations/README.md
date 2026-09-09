# 여러 객체 타입 사이의 참조

한 바인딩 document에 opaque 타입 두 개를 노출하고 한 객체의 메서드가 다른 객체를 호출 동안
빌려 받는 관계를 보여 줍니다.

## 전제 조건

저장소 전체를 받은 뒤 이 예제 디렉터리에서 실행합니다. Zig 0.16.0, Go 1.24 이상,
`gofmt`와 cgo용 C 컴파일러가 필요합니다.
도구 버전과 플랫폼 조건은 [지원 범위](../../docs/reference/support-matrix.md)를 확인하세요.

## 실행

```sh
zig build go
(cd go && go test -count=1 ./...)
```

## 예상 결과

Go 테스트가 통과하며 `Counter`와 `Accumulator` 사이의 호출과 객체 해제를 검증합니다.

## 핵심 파일

- [src/root.zig](src/root.zig) — `Counter`와 `Accumulator`
- [src/bindings.zig](src/bindings.zig) — 타입별 Context와 네임스페이스 선언
- `go/type_relations` — 생성자, 메서드와 수명 테스트

## 동작과 주의사항

`Accumulator.Absorb`는 `Counter`를 borrowed argument로 받지만 그 소유권을 가져가지 않습니다.
따라서 두 생성자가 성공한 뒤 각 객체를 별도로 `Close`해야 합니다. 메서드의 receiver 타입과
인자가 참조하는 타입이 달라도 각 핸들의 유효성을 검사합니다.

```go
counter, err := NewCounter(40)
if err != nil { return err }
defer counter.Close()

accumulator, err := NewAccumulator()
if err != nil { return err }
defer accumulator.Close()

_, err = accumulator.Absorb(counter)
```

## 관련 문서

[객체와 수명](../../docs/authoring/objects-and-lifetimes.md) ·
[Binding API](../../docs/reference/binding-api.md) · [예제 선택](../../docs/examples.md)
