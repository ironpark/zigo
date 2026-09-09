# Go 콜백과 애플리케이션 오류

Go 함수를 Zig에 넘기고 콜백이 반환한 오류나 panic을 다시 Go 호출 경계에서 처리하는
예제입니다.

## 전제 조건

저장소 전체를 받은 뒤 이 예제 디렉터리에서 실행합니다. Zig 0.16.0, Go 1.24 이상,
`gofmt`와 cgo용 C 컴파일러가 필요합니다. zlib 개발 라이브러리도 설치되어 있어야 합니다.
purego 테스트도 Zig로 빌드한 공유 라이브러리를 사용합니다. 로드 설정은 이 예제에 포함되어 있습니다.
도구 버전과 플랫폼 조건은 [지원 범위](../../docs/reference/support-matrix.md)를 확인하세요.

## 실행

```sh
zig build go
(cd go && go test -run '^Example' -v ./...)
(cd go && go test ./...)

zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

## 예상 결과

`ExampleApply`는 원래 애플리케이션 오류를 `errors.Is`로 찾은 결과 `true`를 출력합니다.

## 핵심 파일

- [src/bindings.zig](src/bindings.zig) — 콜백 타입, 수명과 `go_error` 계약
- [Go 사용 예제](go/example_test.go) — 호출 동안 빌리는 콜백
- `go/generated_test.go` — retained 콜백과 제네릭 구체화
- `go/bool_test.go`, `go/bytes_test.go` — bool, 문자열과 바이트 슬라이스 변환
- `go/cancel_test.go`, `go/lifecycle_test.go` — 취소와 수명 경계

## 동작과 주의사항

retained 콜백은 owner가 닫힐 때까지 유지됩니다. owner는 명시적으로 닫고 네이티브 코드는
콜백의 실패 반환값을 처리해야 합니다. Go 오류가 네이티브 실행을 강제로 중단하지는
않습니다. 공개 패키지는 Go 모듈 root에 있으므로 import 경로에 `/callback`을 붙이지 않습니다.

## 관련 문서

[콜백과 오류](../../docs/authoring/callbacks-and-errors.md) ·
[스트림과 취소](../../docs/authoring/streams-and-cancellation.md) ·
[예제 선택](../../docs/examples.md)
