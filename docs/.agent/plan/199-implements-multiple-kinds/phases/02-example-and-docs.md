---
depends_on:
- "199-implements-multiple-kinds#1"
perf_phase: false
status: planned
---
> DONE-WHEN: `cd examples/11-io-streams && zig build test go-check go-lib abi-check`가 통과하고
> NEXT: none

# 예제와 문서

## Planned Work

- `examples/11-io-streams`의 `Document.append`가 `.kinds = &.{ .writer, .string_writer }`를
  쓰도록 바꿔, 메서드 하나가 두 인터페이스를 만족시키는 것을 보여 줍니다. `appendString`은
  string semantic이 붙은 평범한 bound 메서드로 남기고, pass-through 래퍼는 generator case
  골든이 계속 덮습니다.
- 생성 트리(cgo·purego)를 갱신하고 `implements_test.go`에 메서드 하나가 `Write`와
  `WriteString` 양쪽으로 쓰이는 것을 확인하는 테스트를 더합니다.
- `docs/authoring/streams-and-cancellation.md`에 `.kinds`를 적고, 한 메서드가 여러
  인터페이스를 만족시킬 때의 규칙(이름 충돌, 순서)을 함께 씁니다.
- `docs/reference/binding-api.md`의 `.implements` 행을 맞춥니다.
- `CHANGELOG.md`의 `Unreleased`에 항목을 적습니다. `semantic.json` 계약 변화도 함께 적습니다.

## Done When

- `cd examples/11-io-streams && zig build test go-check go-lib abi-check`가 통과하고
  cgo·purego `go test`가 통과한다.
- 예제에서 `append` 하나가 `io.Writer`와 `io.StringWriter`를 모두 만족시킨다.
- 문서 두 곳이 `.kinds`를 설명하고 링크 검사가 깨끗하다.
- `CHANGELOG.md`에 항목이 있다.
