---
completed_at: "2026-09-05T14:17:41Z"
perf_phase: false
status: done
---
> DONE-WHEN: 기존 스냅샷과 생성물이 동일하며 핸들 runtime contracts가 cgo와 purego에서 통과한다.
> NEXT: none

# Handle lifecycle facts in ABI

## Planned Work

- 기존 120 계획 결과를 확인하고 타입별 수명 판정의 소유자를 조사한다.
- parent, borrowed views, retained callbacks 등 파생 사실을 lowering에서 ABI에 기록한다.
- handles와 관련 emitter가 같은 레코드를 읽도록 한다.

## Done When

- 기존 스냅샷과 생성물이 동일하며 핸들 runtime contracts가 cgo와 purego에서 통과한다.
