---
depends_on:
- "70-io-stream-params#2"
perf_phase: false
status: in-progress
---
> DONE-WHEN: 새 예제가 cgo·purego 양쪽에서 `zig build test go-check abi-check` + `go vet` + `go test` 통과. 문서 갱신.
> NEXT: none

# 예제, 테스트, 문서

## Planned Work

- `examples/11-io-streams`(cgo + purego): `Document.dump(w: *std.Io.Writer) !void`(버퍼보다 큰 출력), `Document.load(r: *std.Io.Reader) !usize`, 자유 함수 하나. Go 테스트: `bytes.Buffer` 왕복, 버퍼 크기 대비 `Write` 호출 수 상한, 실패 writer의 error가 `errors.Is`로 식별, 패닉 writer가 `ErrCallbackPanic`, `io.LimitReader`로 EOF, `param_meta.buffer` 변경 시 호출 수 변화.
- `build.zig` godoc_audit·symbol_audit 목록과 CI 예제 루프에 추가. `docs/examples.md`에 항목.
- 문서: `bindings.md` 스트림 파라미터 절(계약, 버퍼, 스레드 규칙, 미지원 위치), `limitations.md`, `generated-code.md`, `purego.md`, `CHANGELOG.md` Unreleased.

## Done When

- 새 예제가 cgo·purego 양쪽에서 `zig build test go-check abi-check` + `go vet` + `go test` 통과. 문서 갱신.
