---
completed_at: "2026-08-30T09:06:02Z"
depends_on:
- "24-24-adversarial-system-validation#0"
perf_phase: false
status: done
---
> DONE-WHEN: 모든 부정 실험이 의도한 진단과 exit 상태를 보이고 원자성/append-only 불변식이 입증된다.
> NEXT: none

# Mutation and failure atomicity

## Planned Work

- 임시 예제 복제본에서 생성 Go 파일과 semantic ABI를 변형해 stale/ABI gate를 검증한다.
- invalid semantic, invalid errors.lock 및 allocation failure가 출력 트리를 보존하는지 검증한다.
- 예상과 다른 동작을 회귀 테스트로 고정하고 수정한다.

## Done When

- 모든 부정 실험이 의도한 진단과 exit 상태를 보이고 원자성/append-only 불변식이 입증된다.
