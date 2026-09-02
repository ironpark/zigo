---
description: 메서드가 receiver 소유의 handle을 빌린 형태(.returns = .borrowed)로 반환하는 경로
plan_status: in-progress
registered_at: "2026-09-02T19:20:25Z"
---
> NEXT: 빌린 handle의 수명 정책을 정하고 `.returns = .borrowed` 명시를 reflection·validate에 반영한다. ([Phase 0](phases/00-policy-and-semantic.md))

# Phases

- [ ] [Phase 00: 수명 정책 결정과 reflection/validate](phases/00-policy-and-semantic.md)
- [ ] [Phase 01: cgo·purego emit](phases/01-emit.md)
- [ ] [Phase 02: 예제, 문서, CHANGELOG](phases/02-example-and-docs.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`.
- 전 예제 루프(cgo·purego), 예제 Go 테스트 `-race`, 골든 갱신은 실패 출력의 actual 경로 사용.

# Decisions That Constrain Ordering

0 → 1 → 2. 플랜 83(공용 lifecycle 런타임) 완료 후 시작한다.

# Next Implementation Target

빌린 handle의 수명 정책을 정하고 `.returns = .borrowed` 명시를 reflection·validate에 반영한다.
