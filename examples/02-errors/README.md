# Zig 오류를 Go에서 처리하기

Zig error union의 성공값을 받고 실패를 Go `error`와 `errors.Is`로 구분하는 예제입니다.

## 실행

```sh
zig build go
(cd go && go test -run '^Example' -v ./...)
(cd go && go test ./...)
```

`ExampleDivide`는 정상 결과 `4`와 0으로 나눈 오류의 판별 결과 `true`를 출력합니다.

## 핵심 파일

- [src/root.zig](src/root.zig) — `Divide` error union과 추가 타입
- [src/bindings.zig](src/bindings.zig) — 공개 함수와 오류 선언
- [Go 사용 예제](go/errors/example_test.go) — 성공·실패 경로
- `go/support/ffi` — 이 예제에서 지정한 raw package

## 생성되는 동작

Zig error set은 Go에서 `errors.Is`로 비교할 수 있는 오류 값이 됩니다. 공개 사용자는 raw
package가 아니라 `errors` package만 import합니다. 예상하지 않은 오류를 예제 테스트에서는
panic으로 드러내지만 실제 application에서는 반환하거나 해당 작업을 중단해야 합니다.

## 다음 문서

[콜백과 오류](../../docs/authoring/callbacks-and-errors.md) ·
[타입 대응](../../docs/reference/type-mapping.md) · [예제 선택](../../docs/examples.md)
