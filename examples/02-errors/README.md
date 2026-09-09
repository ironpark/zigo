# Zig 오류를 Go에서 처리하기

Zig 오류 유니온의 성공값을 받고 실패를 Go `error`와 `errors.Is`로 구분하는 예제입니다.

## 전제 조건

저장소 전체를 받은 뒤 이 예제 디렉터리에서 실행합니다. Zig 0.16.0, Go 1.24 이상,
`gofmt`와 cgo용 C 컴파일러가 필요합니다.
도구 버전과 플랫폼 조건은 [지원 범위](../../docs/reference/support-matrix.md)를 확인하세요.

## 실행

```sh
zig build go
(cd go && go test -run '^Example' -v ./...)
(cd go && go test ./...)
```

## 예상 결과

`ExampleDivide`는 정상 결과 `4`와 0으로 나눈 오류의 판별 결과 `true`를 출력합니다.

## 핵심 파일

- [src/root.zig](src/root.zig) — `Divide` 오류 유니온과 추가 타입
- [src/bindings.zig](src/bindings.zig) — 공개 함수와 오류 선언
- [Go 사용 예제](go/errors/example_test.go) — 성공·실패 경로
- `go/support/ffi` — 이 예제에서 지정한 raw 패키지

## 동작과 주의사항

Zig 오류 집합은 Go에서 `errors.Is`로 비교할 수 있는 오류 값이 됩니다. 공개 사용자는 raw
패키지가 아니라 `errors` 패키지만 import합니다. 예상하지 않은 오류를 예제 테스트에서는
panic으로 드러내지만 실제 애플리케이션에서는 반환하거나 해당 작업을 중단해야 합니다.

## 관련 문서

[콜백과 오류](../../docs/authoring/callbacks-and-errors.md) ·
[타입 대응](../../docs/reference/type-mapping.md) · [예제 선택](../../docs/examples.md)
