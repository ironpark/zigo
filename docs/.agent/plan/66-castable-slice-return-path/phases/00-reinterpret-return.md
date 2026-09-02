---
perf_phase: true
status: in-progress
---
> DONE-WHEN: 측정 목표 세 항목의 테스트 통과.
> NEXT: none

# 적격 struct 슬라이스 반환의 재해석

## Planned Work

- `emit.zig`에 재해석 도우미 출력과 세 반환 지점의 분기 추가. 적격 타입의 `SliceFromRaw` 생성 제거. import 블록 조건 갱신.
- 단위 테스트: 적격 `Point` 반환 골든에 `SliceFromRaw` 부재·재해석 존재, 비적격 `Config` 반환은 `SliceFromRaw` 유지, 에러 유니온·tagged union payload 경로 각각.
- 골든·예제 재생성. 예제 중 적격 struct 슬라이스를 반환하는 곳(07-event-queue `limits`류, 09-type-relations)에서 기존 Go 테스트가 값 동일성을 계속 검증하는지 확인하고 없으면 하나 추가.
- `docs/generated-code.md` 한 줄.

## Done When

- 측정 목표 세 항목의 테스트 통과.
- `zig build test`, 예제 10개 cgo·purego 4개 통과, `git status` 깨끗.
