---
depends_on:
- "68-ultrasync-followups#1"
perf_phase: true
status: planned
---
> DONE-WHEN: 벤치마크가 저장소에 있고 결과와 판단이 문서에 기록됐다. phase 4 상태가 결과에 맞게 설정됐다(`planr phase set`).
> NEXT: none

# `LockOSThread` 비용 측정

## Planned Work

- 07-event-queue `go/`에 벤치마크: 가벼운 error union 메서드(예: `Enqueue` 또는 더 가벼운 것)의 생성 경로 vs raw를 직접 부르는 대조군(`LockOSThread` 없음, 같은 handle 검사). purego 쪽도 하나.
- 결과(ns/op, 차이, 비율)를 `docs/limitations.md`에 기록하고 phase 4 진입 여부를 판단. 판단 기준: `LockOSThread` 쌍이 가벼운 호출 총비용의 10% 이상이면 phase 4 진행.

## Done When

- 벤치마크가 저장소에 있고 결과와 판단이 문서에 기록됐다. phase 4 상태가 결과에 맞게 설정됐다(`planr phase set`).
