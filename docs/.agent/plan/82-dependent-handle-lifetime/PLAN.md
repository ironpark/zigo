---
completed_at: "2026-09-02T18:47:52Z"
description: 다른 handle에서 생성된 handle의 수명 순서(자식이 부모보다 먼저 닫힘)를 바인딩 메타로 표현
plan_status: done
registered_at: "2026-09-02T17:32:43Z"
---
> NEXT: receiver 생성자 메타로 자식 handle이 부모 Close를 막는 구조를 만든다. ([Phase 0](phases/00-child-handles.md))

# Phases

- [x] [Phase 00: 메타와 Go handle 구조](phases/00-child-handles.md)
- [x] [Phase 01: 예제와 문서](phases/01-example-and-docs.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`.
- 전 예제 루프(cgo·purego), 예제 Go 테스트는 `-race`도 실행.

# Decisions That Constrain Ordering

0 → 1. 우선순위 낮음: 79, 80 이후, 81과 독립.

# Next Implementation Target

receiver 생성자 메타로 자식 handle이 부모 Close를 막는 구조를 만든다.
