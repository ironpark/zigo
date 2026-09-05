# Zig·Go·C 이름의 대응

`HTTPClient` 모듈과 `statusCode` 함수를 노출해 패키지·함수 이름이 어떻게 생성되는지
확인하는 작은 회귀 예제입니다. 실제 HTTP 요청을 보내는 클라이언트는 아닙니다.

## 실행

이 디렉터리에서 실행합니다.

```sh
zig build go
(cd go && go test -v ./...)
zig build go-report
```

[build.zig](build.zig)의 모듈 이름, [src/bindings.zig](src/bindings.zig)의 함수 선택,
`go/http_client`의 `StatusCode`를 비교하세요. 이름 관련 설정을 바꾸는 경우에 유용하며,
기본 학습 순서에서는 건너뛰어도 됩니다.

[이름 설정 가이드](../../docs/bindings-functions.md) · [전체 예제](../../docs/examples.md)
