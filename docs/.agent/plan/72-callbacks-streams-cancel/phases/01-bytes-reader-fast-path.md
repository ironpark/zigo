---
perf_phase: true
status: planned
---
> DONE-WHEN: `bytes.Buffer` 입력에서 콜백 0회 테스트 통과.
> NEXT: none

# `[]byte` 무콜백 Reader 경로

## Planned Work

- 70의 스트림 ABI에 슬라이스 변형 추가(70이 아직 진행 전이면 70에 합쳐 breaking 회피). shim `Reader.fixed` 분기, Go 타입 단정.
- 11-io-streams에 콜백 0회 테스트. 문서.

## Done When

- `bytes.Buffer` 입력에서 콜백 0회 테스트 통과.
