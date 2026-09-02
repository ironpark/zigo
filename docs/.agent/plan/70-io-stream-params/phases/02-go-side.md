---
depends_on:
- "70-io-stream-params#1"
perf_phase: false
status: planned
---
> DONE-WHEN: 골든 Go가 `go vet`을 통과하고 시그니처·error 경로 단정이 통과한다.
> NEXT: none

# Go 트램폴린과 공개 래퍼

## Planned Work

- cgo: 고정 `//export` 트램폴린 2종(스트림 파라미터가 있을 때만), `CallbackState` 확장, short write·EOF·error 저장 규칙.
- purego: 두 고정 시그니처 dispatcher를 기존 registry에 추가.
- 공개 래퍼: `io.Writer`/`io.Reader` 시그니처, nil 검사, call-scoped handle, 호출 뒤 `state.err` 우선 반환, `StreamError` 타입·sentinel(errors 파일, 필요할 때만 생성), rethrow.
- `renderCallbackRethrows`·`functionReachesCallbacks`가 스트림 파라미터를 callback으로 세는지 확인.
- 골든 Go 갱신, `emit.zig` 단위 테스트.

## Done When

- 골든 Go가 `go vet`을 통과하고 시그니처·error 경로 단정이 통과한다.
