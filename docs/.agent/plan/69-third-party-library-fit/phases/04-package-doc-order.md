---
perf_phase: false
status: in-progress
---
> DONE-WHEN: 순서 테스트 통과, 문서·예제 갱신.
> NEXT: none

# 패키지 doc 순서에 `bindings.zig` 복귀

## Planned Work

- `names.zig`: 옵션 → `bindings.zig` `//!` → 루트 `//!` → 기본. 네 경우 테스트.
- `docs/bindings.md`, `docs/configuration.md`: 순서와 "bindings 머리 주석은 Go 독자용으로 쓰라"는 안내. 01-scalar는 루트 `//!` 시연 유지, 07-event-queue는 옵션 시연 유지, bindings `//!` 시연을 하나 추가.

## Done When

- 순서 테스트 통과, 문서·예제 갱신.
