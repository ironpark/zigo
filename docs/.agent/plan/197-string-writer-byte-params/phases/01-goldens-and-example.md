---
depends_on:
- "197-string-writer-byte-params#0"
perf_phase: false
status: planned
---
> DONE-WHEN: `zig build test`가 갱신된 골든과 함께 통과한다.
> NEXT: none

# 골든과 예제

## Planned Work

- `tests/generator_cases/implements_std`(그리고 purego 짝)에 바이트 매개변수
  `.string_writer` 메서드를 하나 더합니다. 기존 string semantic 메서드는 그대로 두어 두
  갈래가 한 골든 안에 나란히 남게 합니다.
- `scripts/update-generator-cases.sh implements_std implements_std_purego`로 `expected/`를
  갱신하고 diff를 검토합니다. 기존 메서드들의 출력이 바뀌지 않았는지 확인합니다.
- `examples/11-io-streams`에 바이트를 받는 메서드를 하나 두고 `.string_writer`를 붙입니다.
  `src/root.zig`, `src/bindings.zig`와 생성 트리(cgo·purego)를 갱신합니다.
- `examples/11-io-streams/go{,-purego}/streams/implements_test.go`에 그 메서드로
  `io.WriteString`이 지나가는 것과, 유효한 UTF-8이 아닌 바이트가 그대로 전달되는 것을
  확인하는 테스트를 더합니다.
- ABI 기준선을 확인합니다. 새 메서드는 심볼을 더하므로 `abi-check`가 무엇을 보고하는지
  확인하고 예제의 기준선 규칙대로 처리합니다.

## Done When

- `zig build test`가 갱신된 골든과 함께 통과한다.
- `cd examples/11-io-streams && zig build test go-check go-lib abi-check --summary all`이
  통과하고 `go test ./...`(cgo)와 `CGO_ENABLED=0 go test ./...`(purego)가 통과한다.
- 새 테스트가 유효하지 않은 UTF-8 바이트를 담은 문자열이 그대로 네이티브에 도달하는 것을
  확인한다.
- 기존 `.string_writer` 메서드의 생성 출력이 바뀌지 않는다.
