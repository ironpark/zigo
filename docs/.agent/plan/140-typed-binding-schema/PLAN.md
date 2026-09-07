---
description: 바인딩 선언을 zigo가 내보내는 타입 구조체로 바꾸고 문법 불일치를 한 번에 정리한다 (0.15.0)
plan_status: in-progress
registered_at: "2026-09-07T04:41:56Z"
---
> NEXT: 스키마 정의와 walk.zig 반영. ([Phase 0](phases/00-schema-and-walk.md))

# Phases

- [x] [Phase 00: Schema and reflection](phases/00-schema-and-walk.md)
- [ ] [Phase 01: Coverage, packages, interfaces](phases/01-coverage-packages.md)
- [ ] [Phase 02: Examples](phases/02-examples.md)
- [ ] [Phase 03: Docs and release](phases/03-docs-and-release.md)

# Shared Verification

각 phase의 Done When. 최종은 `scripts/release.sh 0.15.0`.

# Decisions That Constrain Ordering

0 → 1 → 2 → 3. 반영 코드가 바뀌면 그 테스트가 같은 phase에서 옮겨져야 빌드가 유지된다.

# Next Implementation Target

스키마 정의와 walk.zig 반영.
