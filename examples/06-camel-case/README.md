# Zig·C·Go 이름의 대응

`HTTPClient` module과 `statusCode` 함수를 노출해 package와 함수 이름이 각 계층에서 어떻게
변환되는지 확인하는 작은 회귀 예제입니다. 실제 HTTP client는 아닙니다.

## 실행

```sh
zig build go
(cd go && go test ./...)
zig build go-report
```

## 핵심 파일

- [build.zig](build.zig) — Zig module과 Go module 이름
- [src/bindings.zig](src/bindings.zig) — 함수 선택과 이름 정책
- `go/http_client` — 생성된 `StatusCode`

## 생성되는 동작

Zig identifier, C symbol과 exported Go name은 각 계층의 규칙에 맞춰 생성됩니다. 이름 설정을
바꿨다면 `go-report`로 최종 binding 결정을 확인하세요. 일반적인 기능 학습 순서에서는 이
예제를 건너뛰어도 됩니다.

## 다음 문서

[함수와 패키지](../../docs/authoring/functions-and-packages.md) ·
[Binding API](../../docs/reference/binding-api.md) · [예제 선택](../../docs/examples.md)
