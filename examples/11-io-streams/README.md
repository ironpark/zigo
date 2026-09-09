# Go I/O를 Zig에 연결하기

Go `io.Reader`와 `io.Writer`를 Zig 함수에 전달하고 반대로 native 객체가 Go I/O interface를
구현하도록 생성하는 예제입니다.

## 실행

```sh
zig build go
(cd go && go test -run '^Example' -v ./...)
printf 'hello from Go\n' | (cd go && go run ./cmd/stream-copy)

zig build test go-check abi-check
(cd go && go test ./...)
zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

CLI는 stdin을 Zig `Tee`에 전달해 같은 bytes를 stdout으로 쓰며 전체 입력을 Go buffer에 모으지
않습니다.

## 핵심 파일

- [src/root.zig](src/root.zig) — stream 함수와 native `Source`·`Sink`
- [src/bindings.zig](src/bindings.zig) — stream 계약과 plugin attachment
- [CLI](go/cmd/stream-copy/main.go) — 실제 stdin/stdout 사용
- [Go 사용 예제](go/streams/example_test.go) — memory stream과 `io.ReadAll`
- `go/streams/implements_test.go` — 생성 wrapper와 닫힌 handle 검증

## 생성되는 동작

`Tee`는 Go reader를 Zig가 읽어 Go writer로 전달합니다. `Source`와 `Sink`는 native 객체를 Go I/O로
사용하게 합니다. `Document`에는 `features.implements`가 `Read`, `Write`, `ReadFrom`, `WriteTo`를
만들고 satisfies plugin이 `io.ReadWriteCloser` compile-time assertion을 추가합니다. 마지막 줄의
newline까지 보존해야 하는 복사에는 줄 단위인 `Document.Load` 대신 `Tee`를 사용하세요.

## 다음 문서

[스트림과 취소](../../docs/authoring/streams-and-cancellation.md) ·
[Plugin](../../docs/plugins/README.md) · [예제 선택](../../docs/examples.md)
