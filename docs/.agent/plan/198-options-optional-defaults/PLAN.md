---
description: 옵션의 optional 필드가 null 아닌 Zig 기본값을 가질 때 생성 Go가 컴파일되도록 고친다
plan_status: in-progress
registered_at: "2026-09-12T18:06:44Z"
---
> NEXT: phase 0(`pointer-default-init`)부터 시작합니다: optional 기본값을 포인터로 낼 수 있게 고칩니다. ([Phase 0](phases/00-pointer-default-init.md))

# Phases

- [ ] [Phase 00: 포인터 기본값을 낼 수 있는 초기화](phases/00-pointer-default-init.md)
- [ ] [Phase 01: 골든과 기록](phases/01-golden-and-changelog.md)

# Shared Verification

- `zig build test --summary all`.
- `scripts/update-generator-cases.sh options_required_fields` 후 `git diff`.
- 생성 Go의 컴파일 확인(`go build`).
- `zig fmt --check`.

# Decisions That Constrain Ordering

phase 0이 방출을 고치고 phase 1이 그것을 골든으로 고정합니다.

# Next Implementation Target

phase 0(`pointer-default-init`)부터 시작합니다: optional 기본값을 포인터로 낼 수 있게 고칩니다.
