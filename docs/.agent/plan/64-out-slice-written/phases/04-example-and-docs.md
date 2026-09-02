---
depends_on:
- "64-out-slice-written#3"
perf_phase: false
status: planned
---
> DONE-WHEN: 07-event-queue cgo·purego 테스트가 `written` 계약을 검증하며 통과한다.
> NEXT: none

# 예제 `…Into(dst)` 패턴과 문서

## Planned Work

- `examples/07-event-queue`: `estimate`에 `.written = .return` 적용. `readInto(self, dst: []Stats) usize` (또는 스칼라 `[]f64`용 `…Into`) 추가, `.direction = .out, .written = .return`. `Stats`가 bool을 가지면 bool 없는 struct를 하나 골라 캐스트 경로가 실제로 예제에 나타나게 한다.
- cgo·purego 양쪽 `go test`: 미리 채운 버퍼로 호출해 `written`까지만 바뀌고 그 뒤는 그대로임을 확인. `zig build go`/`-Dpurego=true`로 생성물 갱신, `git status`로 의도 밖 변경 없음 확인.
- `docs/bindings.md`: 함수 메타데이터 표에 `written` 행, "out slice의 `written` 이후 원소는 호출 전 값 그대로"(`io.Reader`와 같은 모양), 슬라이스 반환 소유권 절에 "큰 결과는 out 파라미터로" 권장 패턴과 예제. `:345-349`의 잘못된 서술 정정.
- `docs/limitations.md`: bool 필드 struct는 복사 경로, `.written = .return`의 반환 타입 제한, 뷰 반환을 제공하지 않는 이유 한 줄.
- `docs/generated-code.md`: Go 쪽 레이아웃 가드와 캐스트 경로 설명, cgo·purego가 같은 경로임을 명시.
- `ZIGO017`을 진단 목록 문서(있다면)에 추가.

## Done When

- 07-event-queue cgo·purego 테스트가 `written` 계약을 검증하며 통과한다.
- 세 문서가 갱신되고 `zig build test`, 예제 10개의 cgo·purego 테스트, 모든 `go-check`·`abi-check`가 통과한다.
