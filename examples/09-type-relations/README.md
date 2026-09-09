# 여러 객체 타입 사이의 참조

한 binding document에 opaque type 두 개를 노출하고 한 객체의 method가 다른 객체를 호출 동안
빌려 받는 관계를 보여 줍니다.

## 실행

```sh
zig build test go-check abi-check
zig build go
(cd go && go test -count=1 ./...)
```

## 핵심 파일

- [src/root.zig](src/root.zig) — `Counter`와 `Accumulator`
- [src/bindings.zig](src/bindings.zig) — type별 Context와 namespace 선언
- `go/type_relations` — 생성자, method와 수명 테스트

## 생성되는 동작

`Accumulator.Absorb`는 `Counter`를 borrowed argument로 받지만 그 소유권을 가져가지 않습니다.
따라서 두 생성자가 성공한 뒤 각 객체를 별도로 `Close`해야 합니다. method의 receiver type과
인자가 참조하는 type이 달라도 각 handle의 유효성을 검사합니다.

```go
counter, err := NewCounter(40)
if err != nil { return err }
defer counter.Close()

accumulator, err := NewAccumulator()
if err != nil { return err }
defer accumulator.Close()

_, err = accumulator.Absorb(counter)
```

## 다음 문서

[객체와 수명](../../docs/authoring/objects-and-lifetimes.md) ·
[Binding API](../../docs/reference/binding-api.md) · [예제 선택](../../docs/examples.md)
