---
perf_phase: false
status: in-progress
---
> DONE-WHEN: allocator-first 소멸자 골든이 통과하고 전 검증 루프 녹색, 커밋.
> NEXT: none

# 주입 파라미터 뒤의 receiver

## Planned Work

- `receiverName`/`first_param`/`.destroys` 검사를 주입 무시 기준으로 통일하고 emit 인자 순서를 선언 순서로 맞춘다. 골든·문서·CHANGELOG 갱신.

## Done When

- allocator-first 소멸자 골든이 통과하고 전 검증 루프 녹색, 커밋.
