---
depends_on:
- "71-diagnostics-and-optionals#2"
perf_phase: false
status: planned
---
> DONE-WHEN: fixture 통과, 부재와 빈 슬라이스가 구별되는 Go 테스트.
> NEXT: none

# 슬라이스·문자열 optional

## Planned Work

- `?[]const u8`, `?[]T`, `?[:0]const u8` 파라미터: `ptr == NULL` 부재. Go `*[]T`/`*string`. 반환 `?[]T`: 기존 슬라이스 반환 소유권 규칙 위에 presence(`ptr == NULL`).
- out 슬라이스와의 조합은 거부(의미 불명확). 골든·예제·문서.

## Done When

- fixture 통과, 부재와 빈 슬라이스가 구별되는 Go 테스트.
