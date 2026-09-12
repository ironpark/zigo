---
description: 옵션 선언 안에서 기본값 없는 필드를 Go 위치 인자로 내보내 필수 값과 선택 값을 한 선언으로 섞는다
plan_status: in-progress
registered_at: "2026-09-12T07:29:52Z"
---
> NEXT: phase 0(`required-field-contract`)부터 시작합니다: `ZIGO061`을 필드가 아니라 선언 단위로 보게 고칩니다. ([Phase 0](phases/00-required-field-contract.md))

# Phases

- [x] [Phase 00: 필수 필드와 선택 필드를 나누는 계약](phases/00-required-field-contract.md)
- [x] [Phase 01: 혼합 시그니처 방출](phases/01-mixed-signature-emit.md)
- [ ] [Phase 02: 골든과 문서](phases/02-golden-and-docs.md)

# Shared Verification

- `zig build test` -- 단위 테스트, 진단 스냅샷, 모든 generator case 골든 비교.
- `zig build test -Dtest-filter=<case>` -- 새 골든 케이스만 좁혀 확인.
- `scripts/update-generator-cases.sh <case>` -- 골든 재생성 후 diff 검토.
- `cd examples/07-event-queue && zig build test go-check abi-check --summary all` -- 기존
  `.options` 사용처가 그대로인지 확인.
- `cd examples/07-event-queue/go && go test -count=1 ./...`.
- `gofmt -l`과 `zig fmt --check`, 문서 링크·anchor 검사.

# Decisions That Constrain Ordering

phase 0이 계약을 먼저 넓히지 않으면 phase 1의 방출이 도달할 수 없는 코드가 됩니다.
phase 2의 골든은 방출이 끝난 뒤에만 의미가 있습니다. 세 phase는 순서대로 갑니다.

# Next Implementation Target

phase 0(`required-field-contract`)부터 시작합니다: `ZIGO061`을 필드가 아니라 선언 단위로 보게 고칩니다.
