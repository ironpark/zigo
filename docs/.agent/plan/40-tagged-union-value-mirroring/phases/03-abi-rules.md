---
completed_at: "2026-08-31T09:50:10Z"
depends_on:
- "40-tagged-union-value-mirroring#1"
perf_phase: false
status: done
---
> DONE-WHEN: variant 추가가 projection union에서는 compatible, 값 스냅샷 union에서는 breaking으로
> NEXT: none

# ABI rules

## Planned Work

- abi diff가 값 스냅샷 union의 variant 추가·payload 타입 변경·repr 전환을 breaking으로
  판정하게 한다.
- projection union의 기존 append-compatible 규칙은 그대로 둔다.
- repr별 판정 차이를 진단 메시지에 남긴다.

## Done When

- variant 추가가 projection union에서는 compatible, 값 스냅샷 union에서는 breaking으로
  나오는 CLI 계약 테스트가 있다.
