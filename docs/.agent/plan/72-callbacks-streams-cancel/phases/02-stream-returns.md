---
completed_at: "2026-09-02T11:17:24Z"
perf_phase: false
status: done
---
> DONE-WHEN: fixture·예제 테스트 통과.
> NEXT: none

# Zig가 내주는 스트림

## Planned Work

- 반환 위치 `io_stream` 허용(메서드, borrowed). handle에 `Write`/`Flush`/`Read` 생성, shim export 함수. `io.Copy` 양방향 Go 테스트. 문서.

## Implementation Notes

**확장은 파싱과 lowering 사이의 별도 패스다**(`src/gen/stream_return.zig`). 스트림을 내주는
메서드 하나를 합성 `SemanticFn`으로 바꾼다: writer는 `write`·`flush`, reader는 `read`.
그 뒤로는 평범한 메서드라 헤더·shim·raw·공개 Go가 전부 기존 경로를 탄다. 새 lowering
경로도, 새 `AbiParam.Role`도, C ABI 개념도 늘지 않았다. `semantic.json`에는 확장 전의 Zig
메서드가 남으므로 `abi-diff`는 Zig 표면을 비교한다.

**개수는 `usize`가 아니라 `isize`다.** Go가 `int`로 적어야 `io.Writer`/`io.Reader`를
만족한다. `usize`는 Go `uint`가 되어 인터페이스를 만족하지 못한다.

**`Read`의 EOF.** `readSliceShort`는 끝을 짧은 개수로 알리므로, 공개 Go가 결과 0을
`io.EOF`로 옮긴다(`streamAccessorOp(...) == .read`인 함수에만 삽입).

**포인터는 보관하지 않는다.** shim이 연산마다 헬퍼 `<symbol>_stream`을 내고 그 안에서
접근자를 다시 부른다. 수명 질문은 receiver handle의 기존 획득/해제/poison 규칙이 그대로
답한다 — 닫힌 handle의 `Write`는 `ErrInvalidHandle`이고, 테스트가 그것을 고정한다.

**검증(`ZIGO023` 확장).** 스트림 반환은 (1) 메서드여야 하고 (2) 파라미터가 없어야 하며
(3) error union·optional 안이 아니라 반환 타입 그 자체여야 한다. 셋 다 이유가 다른 메시지다.

**`tests/symbol_audit`** 가 스트림 접근자를 알게 했다: 접근자 심볼은 직접 export되지 않고
마지막 세그먼트를 연산 이름으로 바꾼 것(`zg_sink_writer` → `zg_sink_write`)이 export된다.

예제 11에 `Sink`(writer를 내줌)와 `Source`(reader를 내줌)를 추가하고, `io.Copy` 양방향과
`Source`→`Sink` 직결 복사, EOF 반복, 닫힌 handle 거부를 cgo·purego 양쪽에서 테스트한다.
골든 `io_stream{,_purego}`에도 두 접근자를 추가했다.

## Done When

- fixture·예제 테스트 통과.
