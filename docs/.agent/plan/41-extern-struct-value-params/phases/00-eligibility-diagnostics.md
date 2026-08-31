---
perf_phase: false
status: in-progress
---
> DONE-WHEN: 적격·부적격 semantic 픽스처가 통과와 진단 스냅샷으로 고정된다.
> NEXT: none

# Eligibility and diagnostics

## Planned Work

- validate에 extern struct 필드의 재귀 적격 검사를 추가한다. 슬라이스, 포인터, optional,
  error union, callback, 일반 struct 필드는 거부한다.
- `ZIGO003`의 메시지 범위를 넓히거나 새 코드를 배정해 거부 사유가 된 필드를 지목한다.
- reflector가 필드 타입을 IR에 충분히 싣는지 확인하고 부족하면 보강한다.

## Done When

- 적격·부적격 semantic 픽스처가 통과와 진단 스냅샷으로 고정된다.
- 어떤 입력도 `lower.zig`의 `unreachable`에 도달하지 않는다.
