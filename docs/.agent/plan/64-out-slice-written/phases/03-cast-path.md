---
depends_on:
- "64-out-slice-written#1"
- "64-out-slice-written#2"
perf_phase: true
status: in-progress
---
> DONE-WHEN: 적격 타입 슬라이스 파라미터의 cgo raw 골든에 필드별 복사 루프가 없다.
> NEXT: none

# 캐스트 경로와 out 무복사 진입

## Planned Work

- 공개 계층: 적격 원소 슬라이스 파라미터(in/out)는 `SliceToRaw` 대신 `unsafe.Slice` 재해석으로 `[]raw.TData`를 만든다(빈 슬라이스는 nil). out 복귀 복사 호출 제거. 비적격(bool) 원소의 `.out`은 `make([]TData, len)`만 하고 진입 변환을 하지 않는다.
- cgo raw: 적격 원소 슬라이스는 `(*C.x)(unsafe.Pointer(&values[0]))`를 넘기고 원소별 진입·복귀 루프를 제거. 비적격 `.out`은 진입 변환 없이 `make`, 복귀는 `Written` 만큼.
- purego raw는 이미 주소 전달이므로 변경 없음을 확인만 한다.
- `tests/generator_cases/value_struct`에 bool 없는 struct 슬라이스 in/out fixture 추가(예: `Point` 원소 `[]Point` in 파라미터와 `.out, .written = .return` 파라미터). 골든에 캐스트 경로가 나타나고 복사 루프가 없음을 단정하는 `emit.zig` 단위 테스트 추가.
- borrowed `[]const T` 반환(적격 원소)의 raw 계층 원소별 변환도 `unsafe.Slice` + 한 번의 `copy`로 바꿀 수 있으면 같이 정리한다. 복사 계약은 유지.

## Done When

- 적격 타입 슬라이스 파라미터의 cgo raw 골든에 필드별 복사 루프가 없다.
- `.out` 슬라이스의 공개 골든에 진입 복사가 없다(캐스트·복사 경로 모두).
- `Config`(bool) 경로 골든은 복사 경로를 유지하되 out 진입 변환이 없다.
- `zig build test` 통과, 예제 10개 `go-check` 통과.
