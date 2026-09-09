# Go callback과 애플리케이션 오류

Go 함수를 Zig에 넘기고 callback이 반환한 오류나 panic을 다시 Go 호출 경계에서 처리하는
예제입니다.

## 실행

```sh
zig build go
(cd go && go test -run '^Example' -v ./...)
(cd go && go test ./...)

zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

`ExampleApply`는 원래 application 오류를 `errors.Is`로 찾은 결과 `true`를 출력합니다.

## 핵심 파일

- [src/bindings.zig](src/bindings.zig) — callback type, 수명과 `go_error` 계약
- [Go 사용 예제](go/example_test.go) — 호출 동안 빌리는 callback
- `go/generated_test.go` — retained callback과 generic 구체화
- `go/bool_test.go`, `go/bytes_test.go` — bool, string과 byte slice 변환
- `go/cancel_test.go`, `go/lifecycle_test.go` — 취소와 수명 경계

## 생성되는 동작

retained callback은 owner가 닫힐 때까지 유지됩니다. owner는 명시적으로 닫고 native 코드는
callback의 실패 반환값을 처리해야 합니다. Go 오류가 native 실행을 강제로 중단하지는
않습니다. 공개 package는 Go module root에 있으므로 import path에 `/callback`을 붙이지 않습니다.

## 다음 문서

[콜백과 오류](../../docs/authoring/callbacks-and-errors.md) ·
[스트림과 취소](../../docs/authoring/streams-and-cancellation.md) ·
[예제 선택](../../docs/examples.md)
