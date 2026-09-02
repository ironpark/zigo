---
perf_phase: false
status: planned
---
> DONE-WHEN: `func (t *Terminal) NewStream() (*Stream, error)`가 생성되어 cgo·purego 통과, 커밋.
> NEXT: none

# receiver를 가진 생성자

## Planned Work

- `hasConstructorInit`에서 `receiver != null` 제외 조건 제거.
- cgo·purego emit의 생성자 경로를 receiver 있는 경우로 확장: Go 메서드 시그니처, receiver 획득·poison은 메서드 규칙, 반환 handle은 생성자 규칙(caller 소유, `Close`, boxing).
- abi_diff/report가 receiver 있는 생성자를 올바르게 표시하는지 확인.
- 예제(03 또는 07)에 `fn newStream(gpa: Allocator, terminal: *Terminal) !*Stream` 케이스와 Go 테스트 추가, 골든 추가.

## Done When

- `func (t *Terminal) NewStream() (*Stream, error)`가 생성되어 cgo·purego 통과, 커밋.
