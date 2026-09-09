# Zig·C·Go 이름의 대응

`HTTPClient` 모듈과 `statusCode` 함수를 노출해 패키지와 함수 이름이 각 계층에서 어떻게
변환되는지 확인하는 작은 회귀 예제입니다. 실제 HTTP client는 아닙니다.

## 전제 조건

저장소 전체를 받은 뒤 이 예제 디렉터리에서 실행합니다. Zig 0.16.0, Go 1.24 이상,
`gofmt`와 cgo용 C 컴파일러가 필요합니다.
도구 버전과 플랫폼 조건은 [지원 범위](../../docs/reference/support-matrix.md)를 확인하세요.

## 실행

```sh
zig build go
(cd go && go test ./...)
zig build go-report
```

## 예상 결과

Go 테스트가 통과하고 `go-report`에서 공개 함수 `StatusCode`의 이름을 확인할 수 있습니다.

## 핵심 파일

- [빌드.zig](build.zig) — Zig 모듈과 Go 모듈 이름
- [src/bindings.zig](src/bindings.zig) — 함수 선택과 이름 정책
- `go/http_client` — 생성된 `StatusCode`

## 동작과 주의사항

Zig identifier, C 심볼과 exported Go 이름은 각 계층의 규칙에 맞춰 생성됩니다. 이름 설정을
바꿨다면 `go-report`로 최종 바인딩 결정을 확인하세요. 일반적인 기능 학습 순서에서는 이
예제를 건너뛰어도 됩니다.

## 관련 문서

[함수와 패키지](../../docs/authoring/functions-and-packages.md) ·
[Binding API](../../docs/reference/binding-api.md) · [예제 선택](../../docs/examples.md)
