# GOALS

## Problem and the end result from the user's point of view

Zig 라이브러리는 스트리밍 입출력을 `*std.Io.Writer`/`*std.Io.Reader` 파라미터로 받는 쪽으로 가고 있다(Zig 0.16에서 이 둘은 generic이 아닌 구체 struct이며 `std.Io` 인스턴스를 받지 않는다). zigo는 이 타입을 지원하지 않아 `ZIGO019`로 거부하고, 사용자는 facade에서 버퍼를 만들어 슬라이스로 바꾸거나 파일 fd를 넘기는 우회를 써야 한다. fd 전달은 소유권·nonblocking·Windows HANDLE 문제가 있고 fd 없는 대상(`bytes.Buffer`, 네트워크, gzip)에는 쓸 수 없다.

작업 후: `fn dump(self, w: *std.Io.Writer) !void`는 Go에서 `func (t *T) Dump(w io.Writer) error`가 되고, `fn load(self, r: *std.Io.Reader) !usize`는 `Load(r io.Reader) (uint, error)`가 된다. shim이 `std.Io.Writer`/`Reader` 어댑터를 만들어 `drain`/`stream`이 Go 콜백을 부르고, 버퍼가 찰 때만 경계를 넘는다. Go 쪽 `Write`/`Read`의 error는 Go error 그대로 호출자에게 돌아오고, Go 패닉은 기존 `-3` 경로로 재전파된다.

## Measurable goals

- `*std.Io.Writer`, `*std.Io.Reader` 파라미터 fixture가 cgo·purego 양쪽에서 생성되고, Go 시그니처가 `io.Writer`/`io.Reader`다.
- 버퍼(기본 64 KiB)보다 큰 데이터를 쓰는 예제에서 Go `Write` 호출 수가 `ceil(총량 / 버퍼)` 이하다.
- Go writer가 error를 반환하면 그 error가 `errors.Is`로 식별되어 공개 함수에서 돌아온다. Go writer가 패닉하면 `ErrCallbackPanic`으로 재전파된다.
- 반환 타입, extern struct 필드, callback 시그니처, `.retention = .retained` 위치의 스트림 타입은 이유를 담은 진단으로 거부된다.

## Supported scope and non-goals

지원: 함수·메서드의 call-scoped `*std.Io.Writer`/`*std.Io.Reader` 파라미터, cgo와 purego, 버퍼 크기 `param_meta` 옵션, 문서와 예제.
비목표: 스트림 반환(Zig가 Reader/Writer를 돌려주는 경우), handle에 보관되는 retained 스트림(shim 어댑터가 호출 스택에 살기 때문), `std.Io.File`/fd 전달, `sendFile` 최적화, `std.Io` 인스턴스 자체의 전달(계획 69의 `.io` 주입으로 별도), Go `io.ReaderAt`/`io.Seeker`.

## Reference source / commit / license

- Zig 0.16 std: `~/.zvm/0.16.0/lib/std/Io/Writer.zig`(VTable :20-89, `drain` 계약, `fixed` :125, `Allocating` :2502), `Reader.zig`(VTable :23-99, `stream` 계약, `defaultReadVec` :439), 참조 구현 `std/Io/File/Writer.zig:69-132`, `File/Reader.zig:71-229`.
- zigo callback 메커니즘: `src/reflect/walk.zig:462-487`(fn pointer 반영, userdata는 마지막 `usize`), `src/gen/emit.zig:2486-2540`(cgo `//export` 트램폴린, `-3`), `:1866-1953`(purego registry·dispatcher), `:4579-4592`(call-scoped handle setup), `:4556-4578`(rethrow), `src/gen/validate.zig:16-47`(purego callback 반환은 void/i32만, `ZIGO014`).

## Completion criteria for the whole plan

- 측정 목표 테스트 통과. `zig build test --summary all`, `zig fmt --check build.zig src tests examples`, 예제 10개 cgo·purego 4개와 새 예제의 `go-check`·`abi-check`·`go vet`·`go test`.
- `docs/bindings.md`(스트림 파라미터 절), `docs/limitations.md`, `docs/generated-code.md`(어댑터와 콜백 경로), `docs/purego.md`, `CHANGELOG.md` Unreleased 갱신.
