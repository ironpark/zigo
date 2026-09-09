# Go I/O를 Zig에 연결하기

Go `io.Reader`와 `io.Writer`를 Zig 함수에 전달하고 반대로 네이티브 객체가 Go I/O 인터페이스를
구현하도록 생성하는 예제입니다.

## 전제 조건

저장소 전체를 받은 뒤 이 예제 디렉터리에서 실행합니다. Zig 0.16.0, Go 1.24 이상,
`gofmt`와 cgo용 C 컴파일러가 필요합니다.
purego 테스트도 Zig로 빌드한 공유 라이브러리를 사용합니다. 로드 설정은 이 예제에 포함되어 있습니다.
도구 버전과 플랫폼 조건은 [지원 범위](../../docs/reference/support-matrix.md)를 확인하세요.

## 실행

```sh
zig build go
(cd go && go test -run '^Example' -v ./...)
printf 'hello from Go\n' | (cd go && go run ./cmd/stream-copy)

(cd go && go test ./...)
zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

CLI는 stdin을 Zig `Tee`에 전달해 같은 bytes를 stdout으로 쓰며 전체 입력을 Go 버퍼에 모으지
않습니다.

## 예상 결과

CLI는 입력한 `hello from Go`와 마지막 줄바꿈을 그대로 출력합니다.
`ExampleTee`는 `6 bytes: "hello\n"`, `ExampleSource`는 `native bytes`를 출력합니다.

## 핵심 파일

- [src/root.zig](src/root.zig) — 스트림 함수와 네이티브 `Source`·`Sink`
- [src/bindings.zig](src/bindings.zig) — 스트림 계약과 플러그인 연결
- [CLI](go/cmd/stream-copy/main.go) — 실제 stdin/stdout 사용
- [Go 사용 예제](go/streams/example_test.go) — 메모리 스트림과 `io.ReadAll`
- `go/streams/implements_test.go` — 생성 래퍼와 닫힌 핸들 검증

## 동작과 주의사항

`Tee`는 Go reader를 Zig가 읽어 Go writer로 전달합니다. `Source`와 `Sink`는 네이티브 객체를 Go I/O로
사용하게 합니다. `Document`에는 `features.implements`가 `Read`, `Write`, `ReadFrom`, `WriteTo`를
만들고 satisfies 플러그인이 `io.ReadWriteCloser` 컴파일 시점 assertion을 추가합니다. 마지막 줄의
newline까지 보존해야 하는 복사에는 줄 단위인 `Document.Load` 대신 `Tee`를 사용하세요.

## 관련 문서

[스트림과 취소](../../docs/authoring/streams-and-cancellation.md) ·
[Plugin](../../docs/plugins/README.md) · [예제 선택](../../docs/examples.md)
