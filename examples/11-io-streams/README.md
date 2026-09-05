# Go I/O를 Zig 함수에 연결하기

파일·메모리·stdin/stdout을 `io.Reader`와 `io.Writer`로 받아 Zig가 처리하게 합니다.
반대로 native 객체를 Go의 `io.Reader`·`io.Writer`로 사용하는 흐름도 포함합니다.

## 먼저 실행할 예제

이 디렉터리에서 실행합니다. 명령은 Bash·zsh 기준입니다.

```sh
zig build go
(cd go && go test -run '^Example' -v ./...)
printf 'hello from Go\n' | (cd go && go run ./cmd/stream-copy)
```

마지막 명령은 입력을 Zig `tee` 함수로 전달하고 같은 바이트를 stdout에 출력합니다.
[CLI 소스](go/cmd/stream-copy/main.go)는 실제 파일·표준 스트림을 사용하며,
실패는 stderr와 0이 아닌 종료 코드로 알립니다. 입력 전체를 Go 버퍼에 모으지 않습니다.
이름과 달리 이 예제의 `Tee`는 두 출력으로 분기하지 않고 하나의 reader를 하나의 writer로 복사합니다.

Zig의 복사 루프는 4 KiB 임시 버퍼를 사용합니다. 현재 생성 adapter 둘을
`streamRemaining`으로 직접 연결하면 writer 버퍼가 찬 뒤 진행이 멈출 수 있어, 이 예제에서는
`readSliceShort`와 `writeAll`로 진행을 명시합니다. generator 자체의 adapter 수정은 포함하지 않습니다.

[실행 가능한 Go 사용 예제](go/streams/example_test.go)는 메모리 스트림 복사와
`io.ReadAll`로 native `Source` 읽기를 보여 줍니다.

## API 선택

| 필요한 동작 | 이 예제의 API |
|---|---|
| 기존 Go reader → Zig → 기존 Go writer | `Tee` |
| Zig 객체의 내용을 Go writer로 출력 | `Document.Dump` |
| Go reader에서 줄 단위 데이터를 객체에 추가 | `Document.Load` |
| native 객체에 Go의 `io.Copy`로 쓰기 | `Sink.Write`, `Sink.Flush` |
| native 객체에서 Go의 `io.ReadAll`로 읽기 | `Source.Read` |

`Document.Load`는 newline으로 끝나는 줄을 추가합니다. 마지막 줄의 newline이 없으면 그
조각은 버립니다. 임의 파일의 바이트를 보존하려면 `Tee`나 CLI를 사용하세요.
`Bytes() []byte`가 있는 reader는 빠른 경로에서 읽기 위치가 전진하지 않습니다.
위 예제는 `strings.Reader`를 사용해 이 차이를 피합니다.

## 검증과 추가 기능

```sh
zig build test go-check abi-check
(cd go && go test ./...)
zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

CLI 테스트는 빈 입력, newline 없는 입력, UTF-8, 큰 입력과 reader·writer 오류 보존을
검증합니다. 기존 테스트는 staging 버퍼, short write, EOF, panic, native 객체 수명과
narrow 정수 slice를 추가로 다룹니다. CLI는 cgo 모듈에만 두고 두 백엔드의 공통 동작은
각 모듈의 통합 테스트로 확인합니다.

[스트림 선언 가이드](../../docs/bindings-streams.md) · [전체 예제](../../docs/examples.md)
