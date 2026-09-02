---
perf_phase: false
status: in-progress
---
> DONE-WHEN: 충돌 골든이 컴파일되고 기존 예제 `go-check` 변화 없음, 커밋.
> NEXT: none

# receiver 변수명 충돌 회피

## Planned Work

- `receiverVariableAlloc`에 파라미터 이름 목록을 넘겨 접두 확장 규칙으로 비충돌 이름을 고른다. receiver 이름을 쓰는 모든 emit 지점을 같은 함수로 통일(cgo·purego, snapshot/variant/acquire 등 타입 단위 메서드는 파라미터가 없으므로 현행 유지 가능).
- 골든 케이스 `receiver_name_clash`, 예제에 `t` 파라미터 메서드 추가.
- 기존 예제 생성물 바이트 동일 확인.

## Done When

- 충돌 골든이 컴파일되고 기존 예제 `go-check` 변화 없음, 커밋.
