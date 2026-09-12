---
completed_at: "2026-09-12T05:39:08Z"
depends_on:
- "193-composite-session-handles#1"
perf_phase: false
status: done
---
> DONE-WHEN: 생성된 `Close`가 자식 먼저, primary 나중 순서로 닫는다.
> NEXT: none

# Close 의미론

## Planned Work

- `Close()`를 방출한다. IR의 부모-자식 관계에서 유도한 순서로 자식부터 닫고 primary를
  마지막에 닫는다.
- `sync.Once`로 멱등성과 동시 호출 안전성을 준다. 두 번째 호출은 첫 번째의 결과를
  돌려준다.
- 멤버 하나가 실패해도 나머지를 계속 닫고 `errors.Join`으로 합쳐 돌려준다. 부분 실패
  뒤의 상태를 doc comment에 적는다.
- `nil` 멤버를 건너뛴다.
- `var _ io.Closer = (*Session)(nil)`을 같은 파일에 쓴다. `io` import는 플러그인의
  `imports`로 등록한다.
- 순서, 멱등성, 부분 실패, `nil` 멤버는 골든으로 고정한다. 런타임 동작(두 번 호출, 동시
  호출, 실제 부분 실패)은 핸들이 살아 있는 예제에서 확인하므로 phase 3의 Go 테스트가
  맡는다. 케이스 하네스는 골든 패키지를 컴파일하지 않으므로 `io.Closer` assertion이 실제로
  컴파일되는지도 phase 3에서 함께 확인한다.

## Done When

- 생성된 `Close`가 자식 먼저, primary 나중 순서로 닫는다.
- 두 번 호출과 동시 호출이 안전하고 같은 결과를 준다.
- 자식 `Close` 실패가 primary 닫기를 막지 않고 두 오류가 모두 보고된다.
- `var _ io.Closer = (*Session)(nil)`이 생성되고, 그 컴파일은 phase 3의 예제 빌드가 확인한다.
