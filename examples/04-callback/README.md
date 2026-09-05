# Go 콜백과 애플리케이션 오류

Go 함수를 Zig에 넘기고, 그 함수가 반환한 오류를 다시 Go에서 확인합니다.
가장 작은 흐름은 [ExampleApply](go/example_test.go)입니다.
`errors.Is`로 원래 애플리케이션 오류를 찾는 것까지 실행해 검증합니다.

## 실행

이 디렉터리에서 실행합니다.

```sh
zig build go
(cd go && go test -run '^Example' -v ./...)
(cd go && go test ./...)

zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

`ExampleApply`의 출력은 `true`입니다. 공개 패키지는 Go 모듈 루트에 있으므로 import 경로에
`/callback`을 덧붙이지 않습니다.

## 읽는 순서

1. [src/bindings.zig](src/bindings.zig): 콜백 타입·수명·`go_error` 계약
2. [Go 사용 예제](go/example_test.go): 호출 동안 빌리는 콜백
3. `go/generated_test.go`: retained 콜백과 generic 구체화
4. `go/cancel_test.go`, `go/lifecycle_test.go`: 취소와 수명 경계

retained 콜백은 owner가 닫힐 때까지 유지됩니다. owner는 명시적으로 닫고, native 코드는
콜백의 실패 반환값을 처리해야 합니다. Go 오류가 생긴다고 native 실행이 강제로 중단되지는
않습니다. panic 처리·교체·동시 종료 테스트는 학습의 첫 단계가 아니라 회귀 검증입니다.

[콜백 가이드](../../docs/bindings-callbacks.md) · [전체 예제](../../docs/examples.md)
