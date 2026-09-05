# 여러 객체 타입 사이의 참조

하나의 바인딩 문서에서 opaque 타입 두 개를 노출합니다. `Accumulator.absorb`는
`Accumulator`의 메서드이지만 다른 타입인 `*const Counter`를 호출 동안 빌려 받습니다.
메서드의 소속 타입과 인자의 참조 타입이 달라도 각각의 수명을 검사합니다.

## Go에서 사용

아래 함수는 생성된 `type_relations` 패키지 안에 작성하는 예제입니다. 다른 패키지에서는
해당 패키지를 import하고 생성자 앞에 패키지 이름을 붙이세요.

```go
func absorbExample() (int64, error) {
    counter, err := NewCounter(40)
    if err != nil {
        return 0, err
    }
    defer counter.Close()

    accumulator, err := NewAccumulator()
    if err != nil {
        return 0, err
    }
    defer accumulator.Close()

    return accumulator.Absorb(counter)
}
```

두 생성자와 `Absorb` 모두 오류를 반환합니다. `Counter`의 소유권은 `Accumulator`로
이전되지 않으므로 두 객체를 각각 닫습니다. 예제는 정리를 위해 `defer`를 사용하며
`Close` 반환값은 생략합니다.

## 실행

이 디렉터리에서 실행합니다.

```sh
zig build test go-check abi-check
zig build go
(cd go && go test -count=1 ./...)
```

자세한 계약은 [객체 수명](../../docs/bindings-handles.md),
다른 예제는 [예제 선택 가이드](../../docs/examples.md)를 참고하세요.
