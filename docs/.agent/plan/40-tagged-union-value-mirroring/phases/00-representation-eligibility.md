---
perf_phase: false
status: in-progress
---
> DONE-WHEN: 적격/부적격 semantic 픽스처가 각각 통과와 진단 스냅샷으로 고정된다.
> NEXT: none

# Representation and eligibility

## Planned Work

- `.repr = .tagged_union_value` 를 DSL과 semantic IR에 추가한다.
- reflector가 variant payload 종류를 그대로 IR에 싣는지 확인하고 부족하면 보강한다.
- validate에 적격 조건과 새 진단(`ZIGO011`)을 추가한다. 메시지는 거부 사유가 된 variant와
  대안(`.repr = .tagged_union`)을 지목한다.

## Done When

- 적격/부적격 semantic 픽스처가 각각 통과와 진단 스냅샷으로 고정된다.
- 기존 `.repr = .tagged_union` 케이스의 출력이 바뀌지 않는다.
