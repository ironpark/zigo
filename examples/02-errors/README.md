# Zig 오류를 Go에서 처리하기

`Divide`의 성공값을 받고, 0으로 나눈 오류를 `errors.Is`로 구분합니다.
[실행 가능한 Go 사용 예제](go/errors/example_test.go)는 외부 패키지에서의 import와
정상·실패 경로를 함께 보여 줍니다.

## 실행

이 디렉터리에서 실행합니다.

```sh
zig build go
(cd go && go test -run '^Example' -v ./...)
(cd go && go test ./...)
```

`ExampleDivide`는 `4`, `true`를 순서대로 출력합니다. 사용 예제의 예상하지 않은 오류는
테스트 실패를 위해 panic으로 처리합니다. 실제 애플리케이션에서는 호출자에게 반환하거나
해당 작업을 중단하세요.

먼저 [src/root.zig](src/root.zig)의 error union과 [src/bindings.zig](src/bindings.zig)를
읽으세요. 추가 테스트는 slice 합계, enum과 `u21` 범위 오류를 다룹니다.
`go/support/ffi`는 사용자 지정 raw 경로이며 일반 소비자는 공개 `errors` 패키지만 import합니다.

[오류 처리 가이드](../../docs/bindings-callbacks.md) · [전체 예제](../../docs/examples.md)
