# 객체 생성·사용·Close

상태를 가진 Zig 객체를 Go handle로 사용합니다. [실행 가능한 사용 예제](go/opaque/example_test.go)에서
생성 오류 확인, 메서드 호출, optional 결과의 존재 여부, `defer Close`를 순서대로 확인하세요.

## 실행

이 디렉터리에서 실행합니다.

```sh
zig build go
(cd go && go test -run '^Example' -v ./...)
(cd go && go test ./...)
```

출력은 `3`, `0 false`입니다. 0이라는 값과 결과가 없다는 상태는 서로 다릅니다.
예제에서는 정리를 예약하고 `Close`의 반환값은 생략합니다. 실제 종료 오류를 다뤄야 하는
객체는 반환값도 확인하세요.

## 추가로 확인할 동작

- [바인딩 선언](src/bindings.zig): opaque 타입과 생성자·소멸자
- `generated_test.go`: borrowed view, 값으로 복사하는 handle 인자, 문자열
- `poison_test.go`: native panic 이후 재사용 거부
- `go-purego`: 같은 객체 API의 purego 검증

purego는 별도로 생성·로드합니다.

```sh
zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

객체의 동시 호출 안전성은 Zig 구현에 달려 있습니다. GC에 의한 정리 대신 명시적으로
`Close`하세요. [객체 수명 가이드](../../docs/bindings-handles.md) · [전체 예제](../../docs/examples.md)
