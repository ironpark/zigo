---
perf_phase: false
status: in-progress
---
> DONE-WHEN: 적격 타입의 골든에 Go 쪽 단정이 생성되고, bool 필드 struct(`Config`)에는 생성되지 않는다.
> NEXT: none

# Go 쪽 레이아웃 가드와 캐스트 적격 predicate

## Planned Work

- `src/gen/emit.zig`에 `isCastableValueStruct(program, name)` predicate: ZIGO012 통과 + 재귀적으로 bool 필드 없음.
- 공개 struct 파일에 적격 타입마다 `unsafe.Sizeof(T{}) == unsafe.Sizeof(raw.TData{})` 및 필드별 `unsafe.Offsetof` 동일성을 컴파일 시점 단정(`[1]struct{}{}[a-b]` 배열 인덱스 트릭)으로 생성. 필요한 `unsafe` import를 조건부로 추가.
- cgo raw 파일에 `C.sizeof_x == unsafe.Sizeof(TData{})` 단정 추가(적격 타입).
- 부정 테스트: `tests/`에 필드 순서를 바꾼 Go fixture(생성 골든의 `T` 정의를 손으로 뒤집은 사본)를 `go vet` 또는 `go build`로 컴파일해 실패를 기대하는 테스트를 `build.zig`의 골든 아티팩트 검사(`addGoldenArtifactChecks`) 옆에 추가. `expectExitCode` 또는 `expectStdErrMatch`로 실패를 고정한다.

## Done When

- 적격 타입의 골든에 Go 쪽 단정이 생성되고, bool 필드 struct(`Config`)에는 생성되지 않는다.
- 필드 순서를 바꾼 fixture가 컴파일 실패를 내는 테스트가 통과한다.
